rm -f dist/*
python setup.py sdist --formats=zip
python -m pip install --upgrade --upgrade-strategy only-if-needed --find-links=dist sqlmlutils