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
def execute_query(builder, connection: ConnectionInfo):
    with SQLQueryExecutor(connection=connection) as executor:
        return executor.execute(builder)


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

    def execute(self, builder: SQLBuilder):
        try:
            self._mssqlconn.set_msghandler(_sql_msg_handler)
            self._mssqlconn.execute_query(builder.base_script, builder.params)
            return [row for row in self._mssqlconn]
        except Exception as e:
            raise RuntimeError(str.format("Error in SQL Execution: {error}", error=str(e)))

    def execute_query(self, query, params):
        self._mssqlconn.execute_query(query, params)
        return [row for row in self._mssqlconn]

    def __enter__(self):
        self._mssqlconn = _mssql.connect(server=self._connection.server,
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
