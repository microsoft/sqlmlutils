# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import sqlmlutils


def foo():
    return "bar"


sqlpython = sqlmlutils.SQLPythonExecutor(sqlmlutils.ConnectionInfo(server="localhost", database="master"))
result = sqlpython.execute_function_in_sql(foo)
assert result == "bar"

