# sqlmlutils

sqlmlutils is a python package to help execute Python code on a SQL Server machine. It is built to work with ML Services for SQL Server.

# Installation

Download the zip package file from the dist folder.
From a command prompt, run
```
pip install sqlmlutils
```

Note: If you encounter errors installing the pymssql dependency and your client is a Windows machine, consider 
installing the .whl file at the below link (download the file for your Python version and run pip install): 
https://www.lfd.uci.edu/~gohlke/pythonlibs/#pymssql

If you are developing on your own branch and want to rebuild and install the package, you can use the buildandinstall.cmd script that is included.

# Getting started

Shown below are the important functions sqlmlutils provides:
```python
execute_function_in_sql         # Execute a python function inside the SQL database
execute_script_in_sql           # Execute a python script inside the SQL database
execute_sql_query               # Execute a sql query in the database and return the resultant table

create_sproc_from_function      # Create a stored procedure based on a Python function inside the SQL database
create_sproc_from_script        # Create a stored procedure based on a Python script inside the SQL database
check_sproc                     # Check whether a stored procedure exists in the SQL database
drop_sproc                      # Drop a stored procedure from the SQL database
execute_sproc                   # Execute a stored procedure in the SQL database 

install_package                 # Install a Python package on the SQL database
remove_package                  # Remove a Python package from the SQL database
list                            # Enumerate packages that are installed on the SQL database
get_packages_by_user            # Enumerate external libraries installed by specific user in specific scope
```

# Examples

### Execute in SQL
##### Execute a python function in database

```python
import sqlmlutils

def foo():
    return "bar"

# For Linux SQL Server, you must specify the ODBC Driver and the username/password because there is no Trusted_Connection/Implied Authentication support yet.
# connection = sqlmlutils.ConnectionInfo(driver="ODBC Driver 13 for SQL Server", server="localhost", database="master", uid="username", pwd="password")

connection = sqlmlutils.ConnectionInfo(server="localhost", database="master")

sqlpy = sqlmlutils.SQLPythonExecutor(connection)
result = sqlpy.execute_function_in_sql(foo)
assert result == "bar"
```

##### Generate a scatter plot without the data leaving the machine

```python
import sqlmlutils
from PIL import Image


def scatter_plot(input_df, x_col, y_col):
    import matplotlib.pyplot as plt
    import io

    title = x_col + " vs. " + y_col

    plt.scatter(input_df[x_col], input_df[y_col])
    plt.xlabel(x_col)
    plt.ylabel(y_col)
    plt.title(title)

    # Save scatter plot image as a png
    buf = io.BytesIO()
    plt.savefig(buf, format="png")
    buf.seek(0)

    # Returns the bytes of the png to the client
    return buf

# For Linux SQL Server, you must specify the ODBC Driver and the username/password because there is no Trusted_Connection/Implied Authentication support yet.
# connection = sqlmlutils.ConnectionInfo(driver="ODBC Driver 13 for SQL Server", server="localhost", database="AirlineTestDB", uid="username", pwd="password")

connection = sqlmlutils.ConnectionInfo(server="localhost", database="AirlineTestDB")

sqlpy = sqlmlutils.SQLPythonExecutor(connection)

sql_query = "select top 100 * from airline5000"
plot_data = sqlpy.execute_function_in_sql(func=scatter_plot, input_data_query=sql_query,
                                          x_col="ArrDelay", y_col="CRSDepTime")
im = Image.open(plot_data)
im.show()
```

##### Perform linear regression on data stored in SQL Server without the data leaving the machine

You can use the AirlineTestDB (supplied as a .bak file above) to run these examples.

```python
import sqlmlutils

def linear_regression(input_df, x_col, y_col):
    from sklearn import linear_model

    X = input_df[[x_col]]
    y = input_df[y_col]

    lr = linear_model.LinearRegression()
    lr.fit(X, y)

    return lr

# For Linux SQL Server, you must specify the ODBC Driver and the username/password because there is no Trusted_Connection/Implied Authentication support yet.
# connection = sqlmlutils.ConnectionInfo(driver="ODBC Driver 13 for SQL Server", server="localhost", database="AirlineTestDB", uid="username", pwd="password")

connection = sqlmlutils.ConnectionInfo(server="localhost", database="AirlineTestDB")

sqlpy = sqlmlutils.SQLPythonExecutor(connection)
sql_query = "select top 1000 CRSDepTime, CRSArrTime from airline5000"
regression_model = sqlpy.execute_function_in_sql(linear_regression, input_data_query=sql_query,
                                                 x_col="CRSDepTime", y_col="CRSArrTime")
print(regression_model)
print(regression_model.coef_)
```

##### Execute a SQL Query from Python

```python
import sqlmlutils
import pytest

# For Linux SQL Server, you must specify the ODBC Driver and the username/password because there is no Trusted_Connection/Implied Authentication support yet.
# connection = sqlmlutils.ConnectionInfo(driver="ODBC Driver 13 for SQL Server", server="localhost", database="AirlineTestDB", uid="username", pwd="password")

connection = sqlmlutils.ConnectionInfo(server="localhost", database="AirlineTestDB")

sqlpy = sqlmlutils.SQLPythonExecutor(connection)
sql_query = "select top 10 * from airline5000"
data_table = sqlpy.execute_sql_query(sql_query)
assert len(data_table.columns) == 30
assert len(data_table) == 10
```

### Stored Procedure
##### Create and call a T-SQL stored procedure based on a Python function

```python
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

    input_df = pd.read_sql("select top 200 ArrDelay, CRSDepTime from {}".format(input_table), engine).dropna()  
        

    pca = PCA(n_components=2)
    components = pca.fit_transform(input_df)

    output_df = pd.DataFrame(components)
    output_df.to_sql(output_table, engine, if_exists="replace")


# For Linux SQL Server, you must specify the ODBC Driver and the username/password because there is no Trusted_Connection/Implied Authentication support yet.
# connection = sqlmlutils.ConnectionInfo(driver="ODBC Driver 13 for SQL Server", server="localhost", database="AirlineTestDB", uid="username", pwd="password")

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
```

### Package Management

##### In SQL Server 2017, only R package management in Windows is supported.
##### R and Python package management on both Windows and Linux platforms is supported in SQL Server 2019 CTP 2.4 and later.

##### Install and remove packages from SQL Server

```python
import sqlmlutils

# For Linux SQL Server, you must specify the ODBC Driver and the username/password because there is no Trusted_Connection/Implied Authentication support yet.
# connection = sqlmlutils.ConnectionInfo(driver="ODBC Driver 13 for SQL Server", server="localhost", database="AirlineTestDB", uid="username", pwd="password")

connection = sqlmlutils.ConnectionInfo(server="localhost", database="AirlineTestDB")
pkgmanager = sqlmlutils.SQLPackageManager(connection)
pkgmanager.install("astor")

def import_astor():
    import astor

# import the astor package to make sure it installed properly
sqlpy = sqlmlutils.SQLPythonExecutor(connection)
val = sqlpy.execute_function_in_sql(import_astor)

pkgmanager.uninstall("astor")
```


# Notes for Developers

### Running the tests

1. Make sure a SQL Server with an updated ML Services Python is running on localhost. 
2. Restore the AirlineTestDB from the .bak file in this repo 
3. Make sure Trusted (Windows) authentication works for connecting to the database
4. Setup a user with db_owner role with uid: "Tester" and password "FakeT3sterPwd!"
    
### Notable TODOs and open issues

1. The pymssql library is hard to install. Users need to install the .whl files from the link above, not
the .whl files currently hosted in PyPI. Because of this, we should consider moving to use pyodbc.
2. Testing from a Linux client has not been performed.
3. The way we get dependencies of a package to install is sort of hacky (parsing pip output)
4. Output Parameter execution currently does not work - can potentially use MSSQLStoredProcedure binding
