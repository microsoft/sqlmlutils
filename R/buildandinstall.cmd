pushd .
cd ..
R -e "if (!require('odbc')) install.packages('odbc')"
R CMD INSTALL --build R
mv sqlmlutils_*.zip R/dist
popd
