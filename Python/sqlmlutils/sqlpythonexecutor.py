# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

from typing import Callable
import dill
from pandas import DataFrame

from .connectioninfo import ConnectionInfo
from .sqlqueryexecutor import execute_query, execute_raw_query
from .sqlbuilder import SpeesBuilder, SpeesBuilderFromFunction, StoredProcedureBuilder, \
    ExecuteStoredProcedureBuilder, DropStoredProcedureBuilder
from .sqlbuilder import StoredProcedureBuilderFromFunction, RETURN_COLUMN_NAME


class SQLPythonExecutor:

    def __init__(self, connection_info: ConnectionInfo):
        self._connection_info = connection_info

    def execute_function_in_sql(self,
                                func: Callable, *args,
                                input_data_query: str = "",
                                **kwargs):
        """Execute a function in SQL Server.

        :param func: function to execute_function_in_sql. NOTE: This function is shipped to SQL as text.
        Functions should be self contained and import statements should be inline.
        :param args: positional args to pass to function to execute_function_in_sql.
        :param input_data_query: sql query to fill the first argument of the function. The argument gets the result of
        the query as a pandas DataFrame (uses the @input_data_1 parameter in sp_execute_external_script)
        :param kwargs: keyword arguments to pass to function to execute_function_in_sql.
        :return: value returned by func

        >>> from sqlmlutils import ConnectionInfo, SQLPythonExecutor
        >>>
        >>> def foo(val1, val2):
        >>>     import math
        >>>     print(val1)
        >>>     return [math.cos(val2), math.cos(val2)]
        >>>
        >>> sqlpy = SQLPythonExecutor(ConnectionInfo("localhost", database="AirlineTestDB"))
        >>> ret = sqlpy.execute_function_in_sql(foo, val1="blah", val2=5)
        blah
        >>> print(ret)
        [0.28366218546322625, 0.28366218546322625]
        """
        rows = execute_query(SpeesBuilderFromFunction(func, input_data_query, *args, **kwargs), self._connection_info)
        return self._get_results(rows)

    def execute_script_in_sql(self,
                              path_to_script: str,
                              input_data_query: str = ""):
        """Execute a script in SQL Server.

        :param path_to_script: file path to Python script to execute.
        :param input_data_query: sql query to fill InputDataSet global variable with.
        (@input_data_1 parameter in sp_execute_external_script)
        :return: None

        """
        try:
            with open(path_to_script, 'r') as script_file:
                content = script_file.read()
            print("File does exist, using " + path_to_script)
        except FileNotFoundError:
            raise FileNotFoundError("File does not exist!")
        execute_query(SpeesBuilder(content, input_data_query=input_data_query), connection=self._connection_info)

    def execute_sql_query(self,
                          sql_query: str,
                          params = ()):
        """Execute a sql query in SQL Server.

        :param sql_query: the sql query to execute in the server
        :return: table returned by the sql_query
        """
        rows = execute_raw_query(conn=self._connection_info, query=sql_query, params=params)
        df = DataFrame(rows)

        # _mssql's execute_query() returns duplicate keys for indexing, we remove them because they are extraneous
        for i in range(len(df.columns)):
            try:
                del df[i]
            except KeyError:
                pass

        return df

    def create_sproc_from_function(self, name: str, func: Callable,
                                   input_params: dict = None, output_params: dict = None):
        """Create a SQL Server stored procedure based on a Python function.
        NOTE: Type annotations are needed either in the function definition or in the input_params dictionary
        WARNING: Output parameters can be used when creating the stored procedure, but Stored Procedures with
        output parameters other than a single DataFrame cannot be executed with sqlmlutils

        :param name: name of stored procedure.
        :param func: function used to define stored procedure. parameters to the function are used to define parameters
        to the stored procedure. type annotations of the parameters are used to infer SQL types of parameters to the
        stored procedure. currently supported type annotations are "str", "int", "float", and "DataFrame".
        :param input_params: optional dictionary of type annotations for each argument to func;
        if func has type annotations this is not necessary. If both are provided, they must match
        :param output_params optional dictionary of type annotations for each output parameter
        :return: True if creation succeeded

        >>> from sqlmlutils import ConnectionInfo, SQLPythonExecutor
        >>>
        >>> def foo(val1: int, val2: str):
        >>>     from pandas import DataFrame
        >>>     print(val2)
        >>>     df = DataFrame()
        >>>     df["col1"] = [val1, val1, val1]
        >>>     return df
        >>>
        >>> sqlpy = SQLPythonExecutor(ConnectionInfo("localhost", database="AutoRegressTestDB"))
        >>> sqlpy.create_sproc_from_function("MyStoredProcedure", foo, with_results_set=True)
        >>>
        >>> # You can execute_function_in_sql the procedure in the usual way from sql: exec MyStoredProcedure 5, 'bar'
        >>> # You can also call the stored procedure from Python
        >>> ret = sqlpy.execute_sproc(name="MyStoredProcedure", val1=5, val2="bar")
        >>> sqlpy.drop_sproc(name="MyStoredProcedure")

        """
        if input_params is None:
            input_params = {}
        if output_params is None:
            output_params = {}
        # Save the stored procedure in database
        execute_query(StoredProcedureBuilderFromFunction(name, func,
                                                         input_params, output_params), self._connection_info)
        return True

    def create_sproc_from_script(self, name: str, path_to_script: str,
                                 input_params: dict = None, output_params: dict = None):
        """Create a SQL Server stored procedure based on a Python script

        :param name: name of stored procedure.
        :param path_to_script: file path to Python script to create a sproc from.
        :param input_params: optional dictionary of type annotations for inputs in the script
        :param output_params optional dictionary of type annotations for each output variable
        :return: True if creation succeeded

        >>> from sqlmlutils import ConnectionInfo, SQLPythonExecutor
        >>>
        >>>
        >>> sqlpy = SQLPythonExecutor(ConnectionInfo("localhost", database="AutoRegressTestDB"))
        >>> sqlpy.create_sproc_from_script(name="script_sproc", path_to_script="path/to/script")
        >>>
        >>> # This will execute the script in sql; with no inputs or outputs it will just run and return nothing
        >>> sqlpy.execute_sproc(name="script_sproc")
        >>> sqlpy.drop_sproc(name="script_sproc")

        """
        if input_params is None:
            input_params = {}
        if output_params is None:
            output_params = {}
        # Save the stored procedure in database
        try:
            with open(path_to_script, 'r') as script_file:
                content = script_file.read()
            print("File does exist, using " + path_to_script)
        except FileNotFoundError:
            raise FileNotFoundError("File does not exist!")

        execute_query(StoredProcedureBuilder(name, content,
                                             input_params, output_params), self._connection_info)
        return True

    def check_sproc(self, name: str) -> bool:
        """Check to see if a SQL Server stored procedure exists in the database.

        >>> from sqlmlutils import ConnectionInfo, SQLPythonExecutor
        >>>
        >>> sqlpy = SQLPythonExecutor(ConnectionInfo("localhost", database="AutoRegressTestDB"))
        >>> if sqlpy.check_sproc("MyStoredProcedure"):
        >>>     print("MyStoredProcedure exists")
        >>> else:
        >>>     print("MyStoredProcedure does not exist")

        :param name: name of stored procedure.
        :return: boolean whether the Stored Procedure exists in the database
        """
        check_query = "SELECT OBJECT_ID (%s, N'P')"
        rows = execute_raw_query(conn=self._connection_info, query=check_query, params=name)
        return rows[0][0] is not None

    def execute_sproc(self, name: str, **kwargs) -> DataFrame:
        """Call a stored procedure on a SQL Server database.
        WARNING: Output parameters can be used when creating the stored procedure, but Stored Procedures with
        output parameters other than a single DataFrame cannot be executed with sqlmlutils

        :param name: name of stored procedure.
        :param kwargs: keyword arguments to pass to stored procedure
        :return: DataFrame representing the output data set of the stored procedure (or empty)
        """
        return DataFrame(execute_query(ExecuteStoredProcedureBuilder(name, **kwargs), self._connection_info))

    def drop_sproc(self, name: str):
        """Drop a SQL Server stored procedure if it exists.

        :param name: name of stored procedure.
        :return: None
        """
        if self.check_sproc(name):
            execute_query(DropStoredProcedureBuilder(name), self._connection_info)

    @staticmethod
    def _get_results(rows):
        hexstring = rows[0][RETURN_COLUMN_NAME]
        return dill.loads(bytes.fromhex(hexstring))
