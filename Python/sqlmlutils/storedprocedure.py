# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

from pandas import DataFrame

from .connectioninfo import ConnectionInfo
from .sqlqueryexecutor import execute_query
from .sqlbuilder import ExecuteStoredProcedureBuilder, DropStoredProcedureBuilder


class StoredProcedure:
    """Represents a SQL Server stored procedure."""

    def __init__(self, name: str, connection: ConnectionInfo):
        """Instantiates a StoredProcedure. Not meant to be called directly, get handles to stored
        procedures using get_sproc.

        :param name: name of stored procedure.
        """
        self._name = name
        self._connection = connection

    def call(self, **kwargs) -> DataFrame:
        """Call a stored procedure on a SQL Server database.

        :param kwargs: keyword arguments to pass to stored procedure
        :return: DataFrame representing the output data set of the stored procedure (or empty)
        """
        return DataFrame(execute_query(ExecuteStoredProcedureBuilder(self._name, **kwargs), self._connection))

    def drop(self):
        """Drop a SQL Server stored procedure.

        :return: None
        """
        execute_query(DropStoredProcedureBuilder(self._name), self._connection)
