# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import _mssql
from .connectioninfo import ConnectionInfo
from .sqlbuilder import SQLBuilder

"""This module is used to actually execute sql queries. It uses the pymssql module under the hood.

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


def _sql_msg_handler(msgstate, severity, srvname, procname, line, msgtext):
    print(msgtext.decode())


class SQLQueryExecutor:

    """_SQLQueryExecutor objects keep a SQL connection open in order to execute_function_in_sql one or more queries.

    This class implements the basic context manager paradigm.
    """

    def __init__(self, connection: ConnectionInfo):
        self._connection = connection

    def execute(self, builder: SQLBuilder, out_file=None, getResults=True):
        try:
            if out_file is not None:
                with open(out_file,"a") as f:
                    if builder.params is not None:
                        script = builder.base_script.replace("%s", "N'%s'")
                        f.write(script % builder.params)
                    else:
                        f.write(builder.base_script)
                    f.write("GO\n")
                    f.write("-----------------------------")
            else:    
                self._mssqlconn.set_msghandler(_sql_msg_handler)
                if getResults:
                    self._mssqlconn.execute_query(builder.base_script, builder.params)
                    return [row for row in self._mssqlconn]
                else:
                    self._mssqlconn.execute_non_query(builder.base_script, builder.params)
                    return []
        except Exception as e:
            raise RuntimeError("Error in SQL Execution") from e

    def execute_query(self, query, params, out_file=None):
        if out_file is not None:
            with open(out_file, "a") as f:
                if params is not None:
                    script = query.replace("%s", "'%s'")
                    f.write(script % params)
                else:
                    f.write(query)
                f.write("GO\n")
                f.write("-----------------------------")
        self._mssqlconn.execute_query(query, params)
        return [row for row in self._mssqlconn]

    def __enter__(self):
        if self._connection.port == "":
            self._mssqlconn = _mssql.connect(server=self._connection.server,
                                            user=self._connection.uid,
                                            password=self._connection.pwd,
                                            database=self._connection.database)
        else:
            self._mssqlconn = _mssql.connect(server=self._connection.server,
                                            port=self._connection.port,
                                            user=self._connection.uid,
                                            password=self._connection.pwd,
                                            database=self._connection.database)
        self._mssqlconn.set_msghandler(_sql_msg_handler)
        return self

    def __exit__(self, exception_type, exception_value, traceback):
        self._mssqlconn.close()


class SQLTransaction:

    def __init__(self, executor: SQLQueryExecutor, name):
        self._executor = executor
        self._name = name

    def begin(self):
        query = """
declare @transactionname varchar(MAX) = %s;
begin tran @transactionname;
        """
        self._executor.execute_query(query, self._name)

    def rollback(self):
        query = """
declare @transactionname varchar(MAX) = %s;
rollback tran @transactionname;
        """
        self._executor.execute_query(query, self._name)

    def commit(self):
        query = """
declare @transactionname varchar(MAX) = %s;
commit tran @transactionname;
        """
        self._executor.execute_query(query, self._name)
