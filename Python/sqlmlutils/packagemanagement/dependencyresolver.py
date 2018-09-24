# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import operator

from distutils.version import LooseVersion


class DependencyResolver:

    def __init__(self, server_packages, target_package):
        self._server_packages = server_packages
        self._target_package = target_package

    def requirement_met(self, upgrade: bool, version: str = None) -> bool:
        exists = self._package_exists_on_server()
        return exists and (not upgrade or
                           (version is not None and self.get_target_server_version() != "" and
                            LooseVersion(self.get_target_server_version()) >= LooseVersion(version)))

    def get_target_server_version(self):
        for package in self._server_packages:
            if package[0].lower() == self._target_package.lower():
                return package[1]
        return ""

    def get_required_installs(self, target_requirements):
        required_packages = []
        for requirement in target_requirements:
            reqmet = any(package[0] == requirement.name for package in self._server_packages)

            for spec in requirement.specs:
                reqmet = reqmet & self._check_if_installed_package_meets_spec(
                    self._server_packages, requirement.name, spec)

            if not reqmet or requirement.name == self._target_package:
                required_packages.append(self.clean_requirement_name(requirement.name))
        return required_packages

    def _package_exists_on_server(self):
        return any([serverpkg[0].lower() == self._target_package.lower() for serverpkg in self._server_packages])

    @staticmethod
    def clean_requirement_name(reqname: str):
        return reqname.replace("-", "_")

    @staticmethod
    def _check_if_installed_package_meets_spec(package_tuples, name, spec):
        op_str = spec[0]
        req_version = spec[1]

        installed_package_name_and_version = [package for package in package_tuples if package[0] == name]
        if not installed_package_name_and_version:
            return False

        installed_package_name_and_version = installed_package_name_and_version[0]
        installed_version = installed_package_name_and_version[1]

        operator_map = {'>': 'gt', '>=': 'ge', '<': 'lt', '==': 'eq', '<=': 'le', '!=': 'ne'}
        return getattr(operator, operator_map[op_str])(LooseVersion(installed_version), LooseVersion(req_version))
