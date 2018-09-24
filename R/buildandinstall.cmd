pushd .
cd ..
R CMD INSTALL --build R
mv sqlmlutils_0.5.0.zip R/dist
popd
