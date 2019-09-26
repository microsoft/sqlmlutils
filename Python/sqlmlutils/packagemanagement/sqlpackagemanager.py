# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import os
import tempfile
import zipfile
import warnings

from sqlmlutils import ConnectionInfo, SQLPythonExecutor
from sqlmlutils.sqlqueryexecutor import execute_query, SQLTransaction
from sqlmlutils.packagemanagement.packagesqlbuilder import clean_library_name
from sqlmlutils.packagemanagement import servermethods
from sqlmlutils.sqlqueryexecutor import SQLQueryExecutor
from sqlmlutils.packagemanagement.dependencyresolver import DependencyResolver
from sqlmlutils.packagemanagement.pipdownloader import PipDownloader
from sqlmlutils.packagemanagement.scope import Scope
from sqlmlutils.packagemanagement import messages
from sqlmlutils.packagemanagement.pkgutils import get_package_name_from_file, get_package_version_from_file
from sqlmlutils.packagemanagement.packagesqlbuilder import CreateLibraryBuilder, DropLibraryBuilder


class SQLPackageManager:

    def __init__(self, connection_info: ConnectionInfo):
        self._connection_info = connection_info
        self._pyexecutor = SQLPythonExecutor(connection_info)

    def install(self,
                package: str,
                upgrade: bool = False,
                version: str = None,
                install_dependencies: bool = True,
                scope: Scope = None,
                out_file: str = None):
        """Install Python package into a SQL Server Python Services environment using pip.

        :param package: Package name to install on the SQL Server. Can also be a filename.
        :param upgrade: If True, will update the package if it exists on the specified SQL Server.
        If False, will not try to update an existing package.
        :param version: Not yet supported. Package version to install. If not specified,
        current stable version for server environment as determined by PyPi/Anaconda repos.
        :param install_dependencies: If True, installs required dependencies of package (similar to how default
        pip install or conda install works). False not yet supported.
        :param scope: Specifies whether to install packages into private or public scope. Default is private scope.
        This installs packages into a private path for the SQL principal you connect as. If your principal has the
        db_owner role, you can also specify scope as public. This will install packages into a public path for all
        users. Note: if you connect as dbo, you can only install packages into the public path.
        :param out_file: INSTEAD of running the actual installation, print the t-sql commands to a text file to use as script.

        >>> from sqlmlutils import ConnectionInfo, SQLPythonExecutor, SQLPackageManager
        >>> connection = ConnectionInfo(server="localhost", database="AirlineTestsDB")
        >>> pyexecutor = SQLPythonExecutor(connection)
        >>> pkgmanager = SQLPackageManager(connection)
        >>>
        >>> def use_tensorflow():
        >>>    import tensorflow as tf
        >>>    node1 = tf.constant(3.0, tf.float32)
        >>>    return str(node1.dtype)
        >>>
        >>> pkgmanager.install("tensorflow")
        >>> ret = pyexecutor.execute_function_in_sql(connection=connection, use_tensorflow)
        >>> pkgmanager.uninstall("tensorflow")

        """
        if not install_dependencies:
            raise ValueError("Dependencies will always be installed - "
                             "single package install without dependencies not yet supported.")
        if scope is None:
            scope = self._get_default_scope()
        
        if os.path.isfile(package):
            self._install_from_file(package, scope, upgrade, out_file=out_file)
        else:
            self._install_from_pypi(package, upgrade, version, install_dependencies, scope, out_file=out_file)

    def uninstall(self, 
                package_name: str, 
                scope: Scope = None,
                out_file: str = None):
        """Remove Python package from a SQL Server Python environment.

        :param package_name: Package name to remove on the SQL Server.
        :param scope: Specifies whether to uninstall packages from private or public scope. Default is private scope.
        This uninstalls packages from a private path for the SQL principal you connect as. If your principal has the
        db_owner role, you can also specify scope as public. This will uninstall packages from a public path for all
        users. Note: if you connect as dbo, you can only uninstall packages from the public path.
        :param out_file: INSTEAD of running the actual installation, print the t-sql commands to a text file to use as script.
        """
            
        if scope is None:
            scope = self._get_default_scope()
            
        print("Uninstalling " + package_name + " only, not dependencies")
        self._drop_sql_package(package_name, scope, out_file)

    def list(self):
        """List packages installed on server, similar to output of pip freeze.

        :return: List of tuples, each tuple[0] is package name and tuple[1] is package version.
        """
        return self._pyexecutor.execute_function_in_sql(servermethods.show_installed_packages)

    def _get_default_scope(self):
        query = "SELECT IS_SRVROLEMEMBER ('sysadmin') as is_sysadmin"
        is_sysadmin = self._pyexecutor.execute_sql_query(query)["is_sysadmin"].iloc[0]
        return Scope.public_scope() if is_sysadmin == 1 else Scope.private_scope()
        
    def _get_packages_by_user(self, owner='', scope: Scope=Scope.private_scope()):
        has_user = (owner != '')

        query = "DECLARE @principalId INT;  \
                DECLARE @currentUser NVARCHAR(128);  \
                SELECT @currentUser = "

        if has_user:
            query += "%s;\n"
        else:
            query += "CURRENT_USER;\n"

        query += "SELECT @principalId = USER_ID(@currentUser);  \
                       SELECT name, language, scope   \
                       FROM sys.external_libraries AS elib   \
                       WHERE elib.principal_id=@principalId   \
                       AND elib.language='Python' AND elib.scope={0}   \
                       ORDER BY elib.name ASC;".format(1 if scope == Scope.private_scope() else 0)
        return self._pyexecutor.execute_sql_query(query, owner)

    def _drop_sql_package(self, sql_package_name: str, scope: Scope, out_file: str):
        builder = DropLibraryBuilder(sql_package_name=sql_package_name, scope=scope)
        execute_query(builder, self._connection_info, out_file)

    # TODO: Support not dependencies
    def _install_from_pypi(self,
                           target_package: str,
                           upgrade: bool = False,
                           version: str = None,
                           install_dependencies: bool = True,
                           scope: Scope = Scope.private_scope(),
                           out_file: str = None):

        if not install_dependencies:
            raise ValueError("Dependencies will always be installed - "
                             "single package install without dependencies not yet supported.")

        if version is not None:
            target_package = target_package + "==" + version

        with tempfile.TemporaryDirectory() as temporary_directory:
            pipdownloader = PipDownloader(self._connection_info, temporary_directory, target_package)
            target_package_file = pipdownloader.download_single()
            self._install_from_file(target_package_file, scope, upgrade, out_file=out_file)

    def _install_from_file(self, target_package_file: str, scope: Scope, upgrade: bool = False, out_file: str = None):
        name = get_package_name_from_file(target_package_file)
        version = get_package_version_from_file(target_package_file)

        resolver = DependencyResolver(self.list(), name)
        if resolver.requirement_met(upgrade, version):
            serverversion = resolver.get_target_server_version()
            print(messages.no_upgrade(name, serverversion, version))
            return

        # Download requirements from PyPI
        with tempfile.TemporaryDirectory() as temporary_directory:
            pipdownloader = PipDownloader(self._connection_info, temporary_directory, target_package_file)

            # For now, we download all target package dependencies from PyPI.
            target_package_requirements, requirements_downloaded = pipdownloader.download()

            # Resolve which package dependencies need to be installed or upgraded on server.
            required_installs = resolver.get_required_installs(target_package_requirements)
            dependencies_to_install = self._get_required_files_to_install(requirements_downloaded, required_installs)
            
            self._install_many(target_package_file, dependencies_to_install, scope, out_file=out_file)

    def _install_many(self, target_package_file: str, dependency_files, scope: Scope, out_file:str=None):
        target_name = get_package_name_from_file(target_package_file)

        with SQLQueryExecutor(connection=self._connection_info) as sqlexecutor:
            transaction = SQLTransaction(sqlexecutor, clean_library_name(target_name) + "InstallTransaction")
            transaction.begin()
            try:
                for pkgfile in dependency_files:
                    self._install_single(sqlexecutor, pkgfile, scope, out_file=out_file)
                self._install_single(sqlexecutor, target_package_file, scope, True, out_file=out_file)
                transaction.commit()
            except Exception as e:
                transaction.rollback()
                raise RuntimeError("Package installation failed, installed dependencies were rolled back.") from e

    @staticmethod
    def _install_single(sqlexecutor: SQLQueryExecutor, package_file: str, scope: Scope, is_target=False, out_file: str=None):
        name = get_package_name_from_file(package_file)
        version = get_package_version_from_file(package_file)

        with tempfile.TemporaryDirectory() as temporary_directory:
            prezip = os.path.join(temporary_directory, name + "PREZIP.zip")
            with zipfile.ZipFile(prezip, 'w') as zipf:
                zipf.write(package_file, os.path.basename(package_file))

            builder = CreateLibraryBuilder(pkg_name=name, pkg_filename=prezip, scope=scope)
            sqlexecutor.execute(builder, out_file=out_file, getResults=False)

    @staticmethod
    def _get_required_files_to_install(pkgfiles, requirements):
        return [file for file in pkgfiles
                if SQLPackageManager._pkgfile_in_requirements(file, requirements)]

    @staticmethod
    def _pkgfile_in_requirements(pkgfile: str, requirements):
        pkgname = get_package_name_from_file(pkgfile)
        return any([DependencyResolver.clean_requirement_name(pkgname.lower()) ==
                    DependencyResolver.clean_requirement_name(req.lower())
                    for req in requirements])
