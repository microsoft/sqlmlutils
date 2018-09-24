# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

from typing import Callable, List
import abc
import dill
import inspect
import textwrap
from pandas import DataFrame
import warnings

RETURN_COLUMN_NAME = "return_val"


"""
_SQLBuilder implementations are used to generate SQL scripts to execute_function_in_sql Python functions and 
create/drop/execute_function_in_sql stored procedures. 

Builder classes use query parametrization whenever possible, falling back to Python string formatting when neccesary.

The main internal function to execute_function_in_sql SQL statements (_execute_query in the _sqlqueryexecutor module) 
takes an implementation _SQLBuilder as an argument.

All _SQLBuilder classes implement a base_script property. This is the text of the SQL query. Some builder classes
return values in their params property.
"""


class SQLBuilder:

    @abc.abstractmethod
    def base_script(self) -> str:
        pass

    @property
    def params(self):
        return None


class SpeesBuilder(SQLBuilder):

    """_SpeesBuilder objects are used to generate exec sp_execute_external_script SQL queries.

    """

    def __init__(self,
                 script: str,
                 with_results_text: str = "",
                 input_data_query: str = "",
                 script_parameters_text: str = ""):
        """Instantiate a _SpeesBuilder object.

        :param script: maps to @script parameter in the SQL query parameter
        :param with_results_text: with results text used to defined the expected data schema of the SQL query
        :param input_data_query: maps to @input_data_1 SQL query parameter
        :param script_parameters_text: maps to @params SQL query parameter
        """
        self._script = script
        self._input_data_query = input_data_query
        self._script_parameters_text = script_parameters_text
        self._with_results_text = with_results_text

    @property
    def base_script(self):
        return """
exec sp_execute_external_script
@language = N'Python',
@script = %s,
@input_data_1 = %s
{script_parameters}
{with_results_text}
        """.format(script_parameters=self._script_parameters_text,
                   with_results_text=self._with_results_text)

    @property
    def params(self):
        return self._script, self._input_data_query


class SpeesBuilderFromFunction(SpeesBuilder):

    """
    _SpeesBuilderFromFunction objects are used to generate SPEES queries based on a function and given arguments.
    """

    _WITH_RESULTS_TEXT = "with result sets((return_val varchar(MAX)))"

    def __init__(self, func: Callable, input_data_query: str = "", *args, **kwargs):
        """Instantiate a _SpeesBuilderFromFunction object.

        :param func: function to execute_function_in_sql on the SQL Server.
        The spees query is built based on this function.
        :param input_data_query: query text for @input_data_1 parameter
        :param args: positional arguments to function call in SPEES
        :param kwargs: keyword arguments to function call in SPEES
        """
        with_inputdf = input_data_query != ""
        self._function_text = self._build_wrapper_python_script(func, with_inputdf, *args, **kwargs)
        super().__init__(script=self._function_text,
                         with_results_text=self._WITH_RESULTS_TEXT,
                         input_data_query=input_data_query)

    # Generates a Python script that encapsulates a user defined function and the arguments to that function.
    # This script is "shipped" over the SQL Server machine.
    # The function is sent as text.
    # The arguments to pass to the function are serialized into their dill hex strings.
    # When with_inputdf is True, it specifies that func will take the magic "InputDataSet" as its first arguments.
    @staticmethod
    def _build_wrapper_python_script(func: Callable, with_inputdf, *args, **kwargs):
        dill.settings['recurse'] = True
        function_text = SpeesBuilderFromFunction._clean_function_text(inspect.getsource(func))
        args_dill = dill.dumps(kwargs).hex()
        pos_args_dill = dill.dumps(args).hex()
        function_name = func.__name__
        return """
{user_function_text} 
        
import dill
import pandas as pd

# serialized keyword arguments
args_dill = bytes.fromhex("{args_dill}")
# serialized positional arguments
pos_args_dill = bytes.fromhex("{pos_args_dill}")

args = dill.loads(args_dill)
pos_args = dill.loads(pos_args_dill)

# user function name
func = {user_function_name}
    
# call user function with serialized arguments
return_val = func{func_arguments}

return_frame = pd.DataFrame()
# serialize results of user function and put in DataFrame for return through SQL Satellite channel
return_frame["return_val"] = [dill.dumps(return_val).hex()]
OutputDataSet = return_frame
""".format(user_function_text=function_text,
           args_dill=args_dill,
           pos_args_dill=pos_args_dill,
           user_function_name=function_name,
           func_arguments=SpeesBuilderFromFunction._func_arguments(with_inputdf))

    # Call syntax of the user function
    # When with_inputdf is true, the user function will always take the "InputDataSet" magic variable as its first
    # arguments.
    @staticmethod
    def _func_arguments(with_inputdf: bool):
        return "(InputDataSet, *pos_args, **args)" if with_inputdf else "(*pos_args, **args)"

    @staticmethod
    def _clean_function_text(function_text):
        return textwrap.dedent(function_text)


class StoredProcedureBuilder(SQLBuilder):

    def __init__(self, name: str, script: str, input_params: dict = None, output_params: dict = None):

        """StoredProcedureBuilder SQL stored procedures based on Python functions.

        :param name: name of the stored procedure
        :param script: function to base the stored procedure on
        :param input_params: input parameters type annotation dictionary for the stored procedure
        :param output_params: output parameters type annotation dictionary from the stored procedure
        """
        if input_params is None:
            input_params = {}
        if output_params is None:
            output_params = {}
        self._script = script
        self._name = name
        self._input_params = input_params
        self._output_params = output_params
        self._param_declarations = ""

        names_of_input_args = list(self._input_params)
        names_of_output_args = list(self._output_params)

        self._in_parameter_declarations = self.get_declarations(names_of_input_args, self._input_params)
        self._out_parameter_declarations = self.get_declarations(names_of_output_args, self._output_params,
                                                                 outputs=True)
        self._script_parameter_text = self.script_parameter_text(names_of_input_args, self._input_params,
                                                                 names_of_output_args, self._output_params)

    @property
    def base_script(self) -> str:
        self._param_declarations = self.combine_in_out(
            self._in_parameter_declarations, self._out_parameter_declarations)

        return """
CREATE PROCEDURE {name} 
    {parameter_declarations} 
AS
EXEC sp_execute_external_script
@language = N'Python',
@script = %s
{script_parameters}
""".format(name=self._name,
           parameter_declarations=self._param_declarations,
           script_parameters=self._script_parameter_text)

    @property
    def params(self):
        return self._script

    def script_parameter_text(self, in_names: List[str], in_types: dict, out_names: List[str], out_types: dict) -> str:
        if not in_names and not out_names:
            return ""

        script_params = ""
        self._script = "\nfrom pandas import DataFrame\n" + self._script

        in_data_name = ""
        out_data_name = ""

        for name in in_names:
            if in_types[name] == DataFrame:
                in_data_name = name
                in_names.remove(name)
                break

        for name in out_names:
            if out_types[name] == DataFrame:
                out_data_name = name
                out_names.remove(name)
                break

        if in_data_name != "":
            script_params += ",\n" + StoredProcedureBuilderFromFunction.get_input_data_set(in_data_name)

        if out_data_name != "":
            script_params += ",\n" + StoredProcedureBuilderFromFunction.get_output_data_set(out_data_name)

        if len(in_names) > 0:
            script_params += ","

        in_params_declaration = out_params_declaration = ""
        in_params_passing = out_params_passing = ""
        if len(in_names) > 0:
            in_params_declaration = self.get_declarations(in_names, in_types)
            in_params_passing = self.get_params_passing(in_names)

        if len(out_names) > 0:
            out_params_declaration = self.get_declarations(out_names, out_types, True)
            out_params_passing = self.get_params_passing(out_names, True)

        params_declaration = self.combine_in_out(in_params_declaration, out_params_declaration)
        params_passing = self.combine_in_out(in_params_passing, out_params_passing)

        if params_declaration != "":
            script_params += "\n@params = N'{params_declarations}',\n    {params_passing}".format(
                 params_declarations=params_declaration,
                 params_passing=params_passing)

        return script_params

    @staticmethod
    def combine_in_out(in_str: str = "", out_str: str = ""):
        result = in_str
        if result != "" and out_str != "":
            result += ",\n    "
        result += out_str
        return result

    @staticmethod
    def get_input_data_set(name):
        return "@input_data_1 = @{name},\n@input_data_1_name = N'{name}'".format(name=name)

    @staticmethod
    def get_output_data_set(name):
        return "@output_data_1_name = N'{name}'".format(name=name)

    @staticmethod
    def get_declarations(names_of_args: List[str], type_annotations: dict, outputs: bool = False):
            return ",\n    ".join(["@" + name + " {sqltype}{output}".format(
                sqltype=StoredProcedureBuilder.to_sql_type(type_annotations.get(name, None)),
                output=" OUTPUT" if outputs else ""
            ) for name in names_of_args])

    @staticmethod
    def to_sql_type(pytype):
        if pytype is None or pytype == str or pytype == DataFrame:
            return "nvarchar(MAX)"
        elif pytype == int:
            return "int"
        elif pytype == float:
            return "float"
        elif pytype == bool:
            return "bit"
        else:
            raise ValueError("Python type: " + str(pytype) + " not supported.")

    @staticmethod
    def get_params_passing(names_of_args, outputs: bool = False):
        return ",\n    ".join(["@" + name + " = " + "@" + name + "{output}".format(output=" OUTPUT" if outputs else "")
                               for name in names_of_args])


class StoredProcedureBuilderFromFunction(StoredProcedureBuilder):

    """Build query text for stored procedures creation based on Python functions.

ex:

name: "MyStoredProcedure"
func:
def foobar(arg1: str, arg2: str, arg3: str):
    print(arg1, arg2, arg3)

===========becomes===================

create procedure MyStoredProcedure @arg1 varchar(MAX), @arg2 varchar(MAX), @arg3 varchar(MAX) as

exec sp_execute_external_script
@language = N'Python',
@script=N'
def foobar(arg1, arg2, arg3):
    print(arg1, arg2, arg3)
foobar(arg1=arg1, arg2=arg2, arg3=arg3)
',
@params = N'@arg1 varchar(MAX), @arg2 varchar(MAX), @arg3 varchar(MAX)',
@arg1 = @arg1,
@arg2 = @arg2,
@arg3 = @arg3
    """

    def __init__(self, name: str, func: Callable,
                 input_params: dict = None, output_params: dict = None):
        """StoredProcedureBuilderFromFunction SQL stored procedures based on Python functions.

        :param name: name of the stored procedure
        :param func: function to base the stored procedure on
        :param input_params: input parameters type annotation dictionary for the stored procedure
        Can you function type annotations instead; if both, they must match
        :param output_params: output parameters type annotation dictionary from the stored procedure
        """
        if input_params is None:
            input_params = {}
        if output_params is None:
            output_params = {}
        self._func = func
        self._name = name
        self._output_params = output_params

        # Get function information
        function_text = textwrap.dedent(inspect.getsource(self._func))

        argspec = inspect.getfullargspec(self._func)
        names_of_input_args = argspec.args
        annotations = argspec.annotations

        if argspec.defaults is not None:
            warnings.warn("Default values are not supported")

        # Figure out input and output parameter dictionaries
        if input_params != {}:
            if annotations != {} and annotations != input_params:
                raise ValueError("Annotations and input_params do not match!")
            self._input_params = input_params
        elif annotations != {}:
            self._input_params = annotations
        elif len(names_of_input_args) == 0:
            self._input_params = {}

        names_of_output_args = list(self._output_params)

        if len(names_of_input_args) != len(self._input_params):
            raise ValueError("Number of argument annotations doesn't match the number of arguments!")
        if set(names_of_input_args) != set(self._input_params.keys()):
            raise ValueError("Names of arguments do not match the annotation keys!")

        calling_text = self.get_function_calling_text(self._func, names_of_input_args)

        output_data_set = None
        for name in names_of_output_args:
            if self._output_params[name] == DataFrame:
                names_of_output_args.remove(name)
                output_data_set = name
                break

        # Creates the base python script to put in the SPEES query.
        # Arguments to function are passed by name into script using SPEES @params argument.
        self._script = """          
{function_text}
{function_call_text}
{ending}
""".format(function_text=function_text, function_call_text=calling_text,
           ending=self.get_ending(self._output_params, output_data_set))

        self._in_parameter_declarations = self.get_declarations(names_of_input_args, self._input_params)
        self._out_parameter_declarations = self.get_declarations(names_of_output_args, self._output_params,
                                                                 outputs=True)
        self._script_parameter_text = self.script_parameter_text(names_of_input_args, self._input_params,
                                                                 list(self._output_params), self._output_params)

    def script_parameter_text(self, in_names: List[str], in_types: dict, out_names: List[str], out_types: dict) -> str:
        if not in_names and not out_names:
            self._script = "\nfrom pandas import DataFrame\n" + self._script
        return super().script_parameter_text(in_names, in_types, out_names, out_types)

    @staticmethod
    def get_function_calling_text(func: Callable, names_of_args: List[str]):
        # For a function named foo with signature def foo(arg1, arg2, arg3)...
        # kwargs_text is 'arg1=arg1, arg2=arg2, arg3=arg3'
        kwargs_text = ", ".join("{}={}".format(name, name) for name in names_of_args)
        # returns 'foo(arg1=arg2, arg2=arg2, arg3=arg3)'
        return "result = " + func.__name__ + "({})".format(kwargs_text)

    # Convert results to Output data frame and Output parameters
    def get_ending(self, output_params: dict, output_data_set: str):
        res = """
if type(result) == DataFrame:
    {result_val}""".format(result_val="{out_df} = result".format(out_df=output_data_set
                                                                 if output_data_set is not None else "OutputDataSet"))

        if len(output_params) > 0 or output_data_set is not None:
            res += """
elif type(result) == dict:
    {output_params}
elif result is not None:
    raise TypeError("Must return a DataFrame or dictionary with output parameters or None") 
""".format(output_params=self.get_output_params(output_params) if len(output_params) > 0 else "pass")
        return res

    @staticmethod
    def get_output_params(output_params: dict):
        return "\n    ".join(['{name} = result["{name}"]'.format(name=name) for name in list(output_params)])


class ExecuteStoredProcedureBuilder(SQLBuilder):

    def __init__(self, name: str, **kwargs):
        self._name = name
        self._kwargs = kwargs

    # Execute the query: exec sproc @var1 = val1, @var2 = val2...
    # Does not work with output parameters
    @property
    def base_script(self) -> str:
        parameters = ", ".join(["@{name} = {value}".format(name=name, value=self.format_value(self._kwargs[name]))
                                for name in self._kwargs])
        return """exec {}  {}""".format(self._name, parameters)

    @staticmethod
    def format_value(value) -> str:
        if isinstance(value, str):
            return "'{}'".format(value)
        elif isinstance(value, int) or isinstance(value, float):
            return str(value)
        elif isinstance(value, bool):
            return str(int(value))
        else:
            raise ValueError("Parameter type {} not supported.".format(str(type(value))))


class DropStoredProcedureBuilder(SQLBuilder):

    def __init__(self, name: str):
        self._name = name

    @property
    def base_script(self) -> str:
        return """
drop procedure {}
""".format(self._name)
