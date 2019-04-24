import os
from sqlmlutils import ConnectionInfo

driver = os.environ['DRIVER'] if 'DRIVER' in os.environ else "SQL Server"
server = os.environ['SERVER'] if 'SERVER' in os.environ else "localhost"
database = os.environ['DATABASE'] if 'DATABASE' in os.environ else "AirlineTestDB"
uid = os.environ['USER'] if 'USER' in os.environ else ""
pwd = os.environ['PASSWORD'] if 'PASSWORD' in os.environ else ""


connection = ConnectionInfo(driver=driver,
                            server=server,
                            database=database,
                            uid=uid,
                            pwd=pwd)