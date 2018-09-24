# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

class Scope:

    def __init__(self, name: str):
        self._name = name

    def __eq__(self, other):
        return self._name == other._name

    @staticmethod
    def public_scope():
        return Scope("public")

    @staticmethod
    def private_scope():
        return Scope("private")


