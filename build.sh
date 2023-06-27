#!/bin/bash
source functions.sh
source log-functions.sh
source str-functions.sh
source file-functions.sh
source aws-functions.sh

code="$WORKSPACE/$CODEBASE_DIR" 

logInfoMessage "I'll do the scanning for $WORKSPACE/$CODEBASE_DIR"
logInfoMessage "Executing command"
logInfoMessage "golint -r $WORKSPACE/$CODEBASE_DIR"
logInfoMessage "I'll scan $WORKSPACE/$CODEBASE_DIR for only severities"

sleep $SLEEP_DURATION

if [ -d $code ];then
  golint -r $WORKSPACE/$CODEBASE_DIR 
  logInfoMessage "Congratulations golint succeeded!!!"
  generateOutput $ACTIVITY_SUB_TASK_CODE true "Congratulations golint scan succeeded!!!"
else
  if [ "$VALIDATION_FAILURE_ACTION" == "FAILURE" ]
  then
    logErrorMessage "$WORKSPACE/$CODEBASE_DIR: No such directory exist"
    logErrorMessage "Please check golint scan failed!!!"
    generateOutput $ACTIVITY_SUB_TASK_CODE false "Please check gloint scan failed!!!"
    exit 1
  else
    logErrorMessage "$WORKSPACE/$CODEBASE_DIR: No such directory exist"
    logWarningMessage "Please check golint scan failed!!!"
    generateOutput $ACTIVITY_SUB_TASK_CODE true "Please check golint scan failed!!!"
  fi
fi

