# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.

import sqlmlutils


def linear_regression(input_df, x_col, y_col):
    from sklearn import linear_model

    X = input_df[[x_col]]
    y = input_df[y_col]

    lr = linear_model.LinearRegression()
    lr.fit(X, y)

    return lr


sqlpy = sqlmlutils.SQLPythonExecutor(sqlmlutils.ConnectionInfo(server="localhost", database="AirlineTestDB"))
sql_query = "select top 1000 CRSDepTime, CRSArrTime from airline5000"
regression_model = sqlpy.execute_function_in_sql(linear_regression, input_data_query=sql_query,
                                                 x_col="CRSDepTime", y_col="CRSArrTime")
print(regression_model)
print(regression_model.coef_)
