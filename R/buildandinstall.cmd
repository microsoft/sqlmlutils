pushd .
cd ..
R -e "install.packages('RODBCext', repos='https://mran.microsoft.com/snapshot/2019-02-01/')"
R CMD INSTALL --build R
mv sqlmlutils_*.zip R/dist
popd
