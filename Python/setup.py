# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

from setuptools import setup

setup(
    name='sqlmlutils',
    packages=['sqlmlutils', 'sqlmlutils/packagemanagement'],
    version='0.7.3',
    url='https://github.com/Microsoft/sqlmlutils/Python',
    license='MIT License',
    desciption='A client side package for working with SQL Server',
    long_description='A client side package for working with SQL Server Machine Learning Python Services. '
                'sqlmlutils enables easy package installation and remote code execution on your SQL Server machine.',
    author='Microsoft',
    author_email='joz@microsoft.com',
    install_requires=[
        'pip',
        'pymssql',
        'dill',
        'pkginfo',
        'requirements-parser',
        'pandas'
    ],
    python_requires='>=3.5'
)
