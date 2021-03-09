del /q dist\*
python.exe setup.py sdist --formats=zip
python.exe setup.py bdist_wheel
pushd dist
python.exe -m pip install --upgrade --upgrade-strategy only-if-needed --find-links=. sqlmlutils
popd
