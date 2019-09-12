#!/bin/bash

# AUTHOR: Engin YUCE <enginy88@gmail.com>
# DESCRIPTION: Shell script for generating XML request and calling XML API to update custom user-group mapping on PANOS.
# VERSION: 1.1
# LICENSE: Copyright 2019 Engin YUCE. Licensed under the Apache License, Version 2.0.


USER_DOMAIN_PREFIX="DOMAIN"
PAN_USERNAME="admin"
PAN_PASSWORD="admin"
PAN_IP="1.2.3.4"
PAN_VSYS="vsys1"
INPUT_PATH="User-Group-Bindings"
GENERATED_XML_FILENAME="Generated-Custom-User-Group-Mappings.xml"


# BELOW THIS LINE, THERE BE DRAGONS!


_checkWorkingDirectory()
{
	ls | grep $(basename $0) &>/dev/null
	if [[ $? != 0 ]]
	then
		echo "Run this script from original location, exiting!" ; exit 1
	fi
}


_checkVariables()
{
	[[ ! -z "$USER_DOMAIN_PREFIX" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$PAN_USERNAME" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$PAN_PASSWORD" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$PAN_IP" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$PAN_VSYS" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$INPUT_PATH" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$GENERATED_XML_FILENAME" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
}

_processInput()
{
	cat $1 | tr [:blank:] ' ' | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' | tr -s [:blank:] | sed '/^$/d' > tempfile
	local DUPLICATES=$(cat tempfile | sort | uniq -id)
	if [[ X"$DUPLICATES" != X"" ]]
	then
		echo "Duplicate user(s) found and fixed in group '$1':"
		echo "$DUPLICATES"
	fi
	cat tempfile | sort | uniq -iu | tr -d '\r' > $1
	rm -f tempfile 2>/dev/null
}


_generateXMLHeader()
{
	local XML_HEADER="<uid-message>
	<version>1.0</version>
	<type>update</type>
	<payload>
		<groups>"
	echo "$XML_HEADER" > $GENERATED_XML_FILENAME
}


_generateXMLFooter()
{
	local XML_FOOTER="		</groups>
	</payload>
</uid-message>"
	echo "$XML_FOOTER" >> $GENERATED_XML_FILENAME
}


_generateXMLEntry()
{
	echo "			<entry name=\"$1\">" >> ../$GENERATED_XML_FILENAME
	echo "				<members>" >> ../$GENERATED_XML_FILENAME
	while IFS="" read -r LINE || [[ -n "$LINE" ]]
	do
		if [[ -z "$LINE" ]]
		then
			continue
		fi
		echo "					<entry name=\"$USER_DOMAIN_PREFIX\\$LINE\"/>" >> ../$GENERATED_XML_FILENAME
	done < $1
	echo "				</members>" >> ../$GENERATED_XML_FILENAME
	echo "			</entry>" >> ../$GENERATED_XML_FILENAME
}


_getAPIKey()
{
	local CALL=$(curl -X GET --insecure -m 5 "https://$PAN_IP/api/?type=keygen&user=$PAN_USERNAME&password=$PAN_PASSWORD" 2>/dev/null)
	if [[ $? != 0 || -z "$CALL" ]]
	then
		echo "Error on curl call, check the IP, exiting!" ; exit 1
	fi
	echo "$CALL" | grep -F -e "response" -e "status" -e "success" &>/dev/null
	if [[ $? != 0 ]]
	then
		echo "Error on curl response, check the PAN credentials, exiting!" ; exit 1
	fi
	KEY=$(echo "$CALL" | sed -n 's/.*<key>\([a-zA-Z0-9=]*\)<\/key>.*/\1/p')
	if [[ $? != 0 ]] && [[ X"$KEY" != X"" ]]
	then
		echo "Error on curl response, cannot parse API key, exiting!" ; exit 1
	fi
}


_callXMLAPI()
{
	local CALL=$(curl -F key="$KEY" --form file=@$GENERATED_XML_FILENAME --insecure -m 5 "https://$PAN_IP/api/?type=user-id&vsys=$PAN_VSYS" 2>/dev/null)
	if [[ $? != 0 || -z "$CALL" ]]
	then
		echo "Error on curl call, check the IP, exiting!" ; exit 1
	fi
	echo "$CALL" | grep -F -e "response" -e "status" -e "success" &>/dev/null
	if [[ $? != 0 ]]
	then
		echo "Error on curl response, check the target VSYS, exiting!" ; exit 1
	fi
	echo "All succeeded, bye!"
}


_main()
{
	_checkWorkingDirectory
	_checkVariables
	_generateXMLHeader
	if [[ ! -d $INPUT_PATH || ! -x $INPUT_PATH ]]
	then
		echo "Error on accessing group folder, check the path, exiting!"
		exit 1
	fi
	cd $INPUT_PATH
	for FILE in *
	do
		local LOOP_COUNT=0
		if [[ ! -f "$FILE" ]]
		then
			echo "Error on accessing group files, check the directory content, exiting!"
			exit 1
		fi
		if [[ ! -r "$FILE" ]]
		then
			echo "Error on reading group files, check the permissions, exiting!"
			exit 1
		fi
		_processInput $FILE
		_generateXMLEntry $FILE
		(( LOOP_COUNT++ ))
		if (( LOOP_COUNT >= 100))
		then
			echo "Error on iterating group files, max loop limit exceeded, exiting!"
			exit 1
		fi
	done
	cd - &> /dev/null
	_generateXMLFooter
	(( LOOP_COUNT == 0)) && { echo "Error on iterating group files, check the directory content, exiting!" ; exit 1 ; }
	_getAPIKey
	_callXMLAPI
}

_main

