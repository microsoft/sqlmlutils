# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

class ConnectionInfo:
    """Information needed to connect to SQL Server.

    """

    def __init__(self, driver: str = "SQL Server", server: str = "localhost", port: str = "", database: str = "master",
                 uid: str = "", pwd: str = ""):
        """
        :param driver: Driver to use to connect to SQL Server.
        :param server: SQL Server hostname or a specific instance to connect to.
        :param port: SQL Server port number.
        :param database: Database to connect to.
        :param uid: uid to connect with. If not specified, utilizes trusted authentication.
        :param pwd: pwd to connect with. If uid is not specified, pwd is ignored; uses trusted auth instead

        >>> from sqlmlutils import ConnectionInfo
        >>> connection = ConnectionInfo(server="ServerName", database="DatabaseName", uid="Uid", pwd="Pwd")
        """
        self._driver = driver
        self._server = server
        self._port = port
        self._database = database
        self._uid = uid
        self._pwd = pwd

    @property
    def driver(self):
        return self._driver

    @property
    def server(self):
        return self._server

    @property
    def port(self):
        return self._port

    @property
    def database(self):
        return self._database

    @property
    def uid(self):
        return self._uid

    @property
    def pwd(self):
        return self._pwd

    @property
    def connection_string(self):
        return "Driver={driver};Server={server};Database={database};{auth};".format(
            driver=self._driver,
            server=self._server if self._port == "" else "{servername},{port}".format(servername=self._server, port=self._port),
            database=self._database,
            auth="Trusted_Connection=Yes" if self._uid == "" else
                 "uid={uid};pwd={pwd}".format(uid=self._uid, pwd=self._pwd)
        )
