# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

import os

from sqlmlutils import ConnectionInfo, Scope

driver = os.environ['DRIVER'] if 'DRIVER' in os.environ else "SQL Server"
server = os.environ['SERVER'] if 'SERVER' in os.environ else "localhost"
database = os.environ['DATABASE'] if 'DATABASE' in os.environ else "AirlineTestDB"
uid = os.environ['USER'] if 'USER' in os.environ else ""
pwd = os.environ['PASSWORD'] if 'PASSWORD' in os.environ else ""

uidAirlineUser = "AirlineUserdbowner"
pwdAirlineUser = os.environ['PASSWORD_AIRLINE_USER'] if 'PASSWORD_AIRLINE_USER' in os.environ else "FakeT3sterPwd!"

scope = Scope.public_scope() if uid == "" else Scope.private_scope()

connection = ConnectionInfo(driver=driver,
                            server=server,
                            database=database,
                            uid=uid,
                            pwd=pwd)

airline_user_connection = ConnectionInfo(driver=driver,
                            server=server,
                            database=database,
                            uid=uidAirlineUser,
                            pwd=pwdAirlineUser)