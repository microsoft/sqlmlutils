# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

from sqlmlutils.sqlqueryexecutor import execute_raw_query


def _get_sql_package_table(connection):
    query = "select * from sys.external_libraries"
    out_df, outparams = execute_raw_query(connection, query)
    return out_df


def _get_package_names_list(connection):
    df = _get_sql_package_table(connection)
    return  {x: y for x, y in zip(df['name'], df['scope'])}
