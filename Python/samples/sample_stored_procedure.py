# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

import sqlmlutils
import pytest

def principal_components(input_table: str, output_table: str):
    import sqlalchemy
    from urllib import parse
    import pandas as pd
    from sklearn.decomposition import PCA

    # Internal ODBC connection string used by process executing inside SQL Server
    connection_string = "Driver=SQL Server;Server=localhost;Database=AirlineTestDB;Trusted_Connection=Yes;"
    engine = sqlalchemy.create_engine("mssql+pyodbc:///?odbc_connect={}".format(parse.quote_plus(connection_string)))

    input_df = pd.read_sql("select top 200 ArrDelay,CRSDepTime,DayOfWeek from {}".format(input_table), engine).dropna()
        

    pca = PCA(n_components=2)
    components = pca.fit_transform(input_df)

    output_df = pd.DataFrame(components)
    output_df.to_sql(output_table, engine, if_exists="replace")


connection = sqlmlutils.ConnectionInfo(server="localhost", database="AirlineTestDB")

input_table = "airline5000"
output_table = "AirlineDemoPrincipalComponents"

sp_name = "SavePrincipalComponents"

sqlpy = sqlmlutils.SQLPythonExecutor(connection)

if sqlpy.check_sproc(sp_name):
    sqlpy.drop_sproc(sp_name)

sqlpy.create_sproc_from_function(sp_name, principal_components)

# You can check the stored procedure exists in the db with this:
assert sqlpy.check_sproc(sp_name)

sqlpy.execute_sproc(sp_name, input_table=input_table, output_table=output_table)

sqlpy.drop_sproc(sp_name)
assert not sqlpy.check_sproc(sp_name)