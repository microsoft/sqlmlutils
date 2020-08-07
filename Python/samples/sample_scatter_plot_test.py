# Copyright(c) Microsoft Corporation.
# Licensed under the MIT license.

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


sqlpy = sqlmlutils.SQLPythonExecutor(sqlmlutils.ConnectionInfo(server="localhost", database="AirlineTestDB"))

sql_query = "select top 100 * from airline5000"
plot_data = sqlpy.execute_function_in_sql(func=scatter_plot, input_data_query=sql_query,
                                          x_col="ArrDelay", y_col="CRSDepTime")
im = Image.open(plot_data)
im.show()
#im.save("scatter_test.png")
