# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

import pyodbc
import sys

from pandas import DataFrame

from .connectioninfo import ConnectionInfo
from .sqlbuilder import SQLBuilder
from .sqlbuilder import STDOUT_COLUMN_NAME, STDERR_COLUMN_NAME

"""This module is used to actually execute sql queries. It uses the pyodbc module under the hood.

It is mostly setup to work with SQLBuilder objects as defined in sqlbuilder.
"""


# This function is best used to execute_function_in_sql a one off query
# (the SQL connection is closed after the query completes).
# If you need to keep the SQL connection open in between queries, you can use the _SQLQueryExecutor class below.
def execute_query(builder, connection: ConnectionInfo, out_file:str=None):
    with SQLQueryExecutor(connection=connection) as executor:
        return executor.execute(builder, out_file=out_file)


def execute_raw_query(conn: ConnectionInfo, query, params=()):
    with SQLQueryExecutor(connection=conn) as executor:
        return executor.execute_query(query, params)

class SQLQueryExecutor:
    """_SQLQueryExecutor objects keep a SQL connection open in order to execute_function_in_sql one or more queries.

    This class implements the basic context manager paradigm.
    """

    def __init__(self, connection: ConnectionInfo):
        self._connection = connection

    def execute(self, builder: SQLBuilder, out_file=None):
        return self.execute_query(builder.base_script, builder.params, out_file=out_file)

    def execute_query(self, query, params, out_file=None):
        df = DataFrame()
        output_params = None

        try:
            if out_file is not None:
                with open(out_file,"a") as f:
                    if params is not None:
                        script = query.replace("?", "N'%s'")

                        # Convert bytearray to hex so user can run as a script
                        #
                        if type(params) is bytearray:
                            params = str('0x' + params.hex())
                            
                        f.write(script % params)
                    else:
                        f.write(query)
                    f.write("GO\n")
                    f.write("-----------------------------")
            else:
                if params is not None:
                    self._cursor.execute(query, params)
                else:
                    self._cursor.execute(query)

                # Get the first resultset (OutputDataSet)
                #
                if self._cursor.description is not None:
                    column_names = [element[0] for element in self._cursor.description]
                    rows = [tuple(t) for t in self._cursor.fetchall()]
                    df = DataFrame(rows, columns=column_names)
                    if STDOUT_COLUMN_NAME in column_names:
                        self.extract_output(dict(zip(column_names, rows[0])))
                
                # Get output parameters
                #
                while self._cursor.nextset(): 
                    try:
                        if self._cursor.description is not None:
                            column_names = [element[0] for element in self._cursor.description]
                            rows = [tuple(t) for t in self._cursor.fetchall()]
                            output_params = dict(zip(column_names, rows[0])) 
                            
                            if STDOUT_COLUMN_NAME in column_names:
                                self.extract_output(output_params)
                            
                    except pyodbc.ProgrammingError:
                        continue
                
        except Exception as e:
            raise RuntimeError("Error in SQL Execution: " + str(e))
        
        return df, output_params

    def __enter__(self):
        server=self._connection._server if self._connection._port == "" \
            else "{server},{port}".format(
                server=self._connection._server, 
                port=self._connection._port
            )

        self._cnxn = pyodbc.connect(self._connection.connection_string,
                                    autocommit=True)
        self._cursor = self._cnxn.cursor()
        return self

    def __exit__(self, exception_type, exception_value, traceback):
        self._cnxn.close()
    
    def extract_output(self, output_params : dict):
        out = output_params.pop(STDOUT_COLUMN_NAME, None)
        err = output_params.pop(STDERR_COLUMN_NAME, None)
        if out is not None:
            print(out)
        if err is not None:
            print(err, file=sys.stderr)