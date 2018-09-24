# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

from sqlmlutils.sqlqueryexecutor import execute_raw_query


def _get_sql_package_table(connection):
    query = "select * from sys.external_libraries"
    return execute_raw_query(connection, query)


def _get_package_names_list(connection):
    return {dic['name']: dic['scope'] for dic in _get_sql_package_table(connection)}
