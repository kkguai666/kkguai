@echo off
rem Runs the gmail.mjs helper on win01 with the proxy env it needs (kept here for reference).
@echo off
set NODE_USE_ENV_PROXY=1
set HTTPS_PROXY=http://127.0.0.1:7897
set HTTP_PROXY=http://127.0.0.1:7897
node "C:\Users\Administrator\.claude\skills\gmail-api\scripts\gmail.mjs" %*
