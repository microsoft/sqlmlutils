# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

import os
from sys import platform

from sqlmlutils import ConnectionInfo, Scope

default_driver = "ODBC Driver 17 for SQL Server" if platform != "win32" else "SQL Server

driver = os.environ['DRIVER'] if 'DRIVER' in os.environ else default_driver
server = os.environ['SERVER'] if 'SERVER' in os.environ else "localhost"
database = os.environ['DATABASE'] if 'DATABASE' in os.environ else "AirlineTestDB"
uid = os.environ['USER'] if 'USER' in os.environ else ""
pwd = os.environ['PASSWORD'] if 'PASSWORD' in os.environ else ""

scope = Scope.public_scope() if uid == "" else Scope.private_scope()


connection = ConnectionInfo(driver=driver,
                            server=server,
                            database=database,
                            uid=uid,
                            pwd=pwd)