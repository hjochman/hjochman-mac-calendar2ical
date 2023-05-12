#!/bin/bash

# Based on:
# Author: Sergios Stamatis
# Company: ITEna Solutions
# Creation Date: 06 March 2012

# MacOS Calendar to ical converter
# Author: Hanspeter Jochmann
# Creation Date: Mai 2023

# Where to grab Calendar.sqlitedb
#CALENDAR_DB_SOURCE=~/Library/Application\ Support/iPhone\ Simulator/5.0/Library/Calendar/Calendar.sqlitedb
CALENDAR_DB_SOURCE=~/Library/Calendars/Calendar.sqlitedb
# Where to put Calendar.sqlitedb
CALENDAR_DB_DESTINATION=~/Desktop
CALENDAR_DB_DESTINATION_FILE=~/Desktop/Calendar.sqlitedb
# ID of the calendar to export
CALENDAR_ID=8
# Tiimeframe to export zo ical
# -v [+|-]val[y|m|w|d|H|M|S]
CALENDAR_START=$(date -v-1m +%s)
CALENDAR_END=$(date -v+1y +%s)

###########  Functions

function fold_long_lines() {
  env LANG="$LANG8BIT" sed -r 's/(.{73})(.)/\1\n \2/g'
}

function lf_to_crlf() {
  sed 's/$/\r/'
}

function crlf_to_lf() {
  tr -d '\r'
}

# &0: standard ical, with long lines wrapped
# &1: long lines are unwrapped
function unwrap_ical_long_lines() {
  sed ':n;N;s/\n //;tn;P;D'
}


# $1: string to encode
function urlencode() {
  local saveLANG="$LANG"
  export LANG="$LANG8BIT"
  local index char

  for (( index=0; index<${#1}; index++ )); do
    char=${1:$index:1}
    case "$char" in
      [-A-Za-z0-9._~]) printf '%s' "$char" ;;
      *) printf '%%%02x' "'$char" ;;
    esac
  done

  export LANG="$saveLANG"
}

function output_ical_header() {
  cat <<-ENDOFTEXT
BEGIN:VCALENDAR
VERSION:2.0
PRODID:hp-jochmann.de/mac-calendar2ical v1.0
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VTIMEZONE
TZID:Europe/Berlin
LAST-MODIFIED:20230411T190536Z
BEGIN:STANDARD
DTSTART:20051030T010000
TZOFFSETTO:+0100
TZOFFSETFROM:+0000
TZNAME:CET
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:20060326T030000
TZOFFSETTO:+0200
TZOFFSETFROM:+0100
TZNAME:CEST
END:DAYLIGHT
END:VTIMEZONE
ENDOFTEXT
}

function output_ical_footer() {
  cat <<-ENDOFTEXT
END:VCALENDAR
ENDOFTEXT
}


truncateFloat () {
# Return the decimal part of the string
  FLOAT=$1
  echo ${FLOAT%.*}
}

extractField () {
# Return database field. Fields are seperated with '|'
  FIELD=$1
  POSITION=$2
  echo ${FIELD} | cut -d '|' -f $POSITION
}

convertMacAbsoluteTimeOld () {
# Convert from Mac Absolute Time to Unix epoch time
# Mac Absolute Time is the number of seconds from 01/01/2001 00:00:00
# sqlite3 requires a database file to be specified to executed queries
  UNIX_TO_MAC_SECONDS=`sqlite3 "${CALENDAR_DB_DESTINATION_FILE}" "select strftime('%s', '2001-01-01 00:00:00');"`
  MAC=$1
  MAC_ROUND=`truncateFloat ${MAC}`
  RESULT=`echo "${MAC_ROUND} + ${UNIX_TO_MAC_SECONDS}" | bc`
  echo `date -r ${RESULT} +%Y%m%dT%H%M%SZ`
}

convertMacAbsoluteTime () {
# Convert from Mac Absolute Time to Unix epoch time
# Mac Absolute Time is the number of seconds from 01/01/2001 00:00:00
# sqlite3 requires a database file to be specified to executed queries
  MAC=$1
  MAC_ROUND=`truncateFloat ${MAC}`
  echo `date -r ${MAC_ROUND} -v+31y -v+1d +%Y%m%dT%H%M%SZ`
}

######  Main ################
CALENDAR_START_MAC=$(date -r ${CALENDAR_START} -v-31y +%s)
CALENDAR_END_MAC=$(date -r ${CALENDAR_END} -v-31y +%s)

cp "${CALENDAR_DB_SOURCE}" "${CALENDAR_DB_DESTINATION}"
CALENDAR_ITEMS=`sqlite3 "${CALENDAR_DB_DESTINATION_FILE}" "select start_date,end_date,last_modified,unique_identifier,location_id,ROWID,has_recurrences,all_day from CalendarItem where calendar_id = ${CALENDAR_ID};"`

#For debug get cal entry by ID
#CALENDAR_ITEMS=`sqlite3 "${CALENDAR_DB_DESTINATION_FILE}" "select start_date,end_date,last_modified,unique_identifier,location_id,ROWID,has_recurrences,all_day from CalendarItem where ROWID = 1699;"`


#sqlite3 "${CALENDAR_DB_DESTINATION_FILE}" "select start_date,end_date,last_modified,unique_identifier,location_id,calendar_id,has_recurrences,UUID from CalendarItem where calendar_id = 8;"
#sqlite3 "${CALENDAR_DB_DESTINATION_FILE}" "select frequency,UUID,owner_id from Recurrence;" # where UUID = \"31C6C1D6-0AEB-44B5-9E92-D6448EB6BBD2\";"
#exit

# To split string on new line character and correctly iterate
# CALENDAR_ITEMS at the for loop
oldIFS=$IFS
IFS='
'

{
output_ical_header

for calendarItem in ${CALENDAR_ITEMS[@]}
do
  #echo "==========> ${CALENDAR_START_MAC}<${START_DATE_RAW%.*}<${CALENDAR_END_MAC} DEBUG: ${calendarItem}"
  START_DATE_RAW=`extractField ${calendarItem} 1`
  END_DATE_RAW=`extractField ${calendarItem} 2`
  LAST_MODIFIED_RAW=`extractField ${calendarItem} 3`
  ITEM=`extractField ${calendarItem} 4`
  LOC_ID=`extractField ${calendarItem} 5`
  EVENT_ID=`extractField ${calendarItem} 6`
  HAS_OC=`extractField ${calendarItem} 7`
  ALL_DAY=`extractField ${calendarItem} 8`
 
  #echo "==========> DEBUG: conv start"
  START_DATE=`convertMacAbsoluteTime $START_DATE_RAW`
  #echo "==========> DEBUG: conv end"
  END_DATE=`convertMacAbsoluteTime $END_DATE_RAW`
  #echo "==========> DEBUG: conv mod"
  if [[ "x$LAST_MODIFIED_RAW" == "x" ]]; then
    LAST_MODIFIED=$(date -u +%Y%m%dT%H%M%SZ) 
  else
    LAST_MODIFIED=`convertMacAbsoluteTime $LAST_MODIFIED_RAW`
  fi
#  LOC=`sqlite3 -separator " " "${CALENDAR_DB_DESTINATION_FILE}" "select title, address from Location where item_owner_id = '${LOC_ID}';" | tr -d '\r'`
  LOC=`sqlite3 -separator " " "${CALENDAR_DB_DESTINATION_FILE}" "select title, address from Location where ROWID = '${LOC_ID}';" | tr -dc '\007-\011\012-\014\040-\376'`
  DESC=`sqlite3 "${CALENDAR_DB_DESTINATION_FILE}" "select description from CalendarItem where unique_identifier = '${ITEM}';" | tr -dc '\007-\011\012-\014\040-\376'` 
  SUMMARY=`sqlite3 "${CALENDAR_DB_DESTINATION_FILE}" "select summary from CalendarItem where unique_identifier = '${ITEM}';" | tr -dc '\007-\011\012-\014\040-\376'` 
  #echo "==========> ${SUMMARY}"

  if [[ $HAS_OC == "0" ]]; then
    if [[ ${CALENDAR_START_MAC} -le ${START_DATE_RAW%.*} ]] && [[ ${CALENDAR_END_MAC} -ge ${START_DATE_RAW%.*} ]] ; then
      printf "BEGIN:VEVENT\nUID:%s\nDTSTAMP;TZID=Europe/Berlin:%s\n" \
             "${ITEM}" "${LAST_MODIFIED}" 
      if [[ $ALL_DAY == "1" ]]; then
        printf "DTSTART;TZID=Europe/Berlin;VALUE=DATE:%s\n" \
               "${START_DATE:0:8}" 
      else
        printf "DTSTART;TZID=Europe/Berlin:%s\nDTEND;TZID=Europe/Berlin:%s\n" \
               "${START_DATE}" "${END_DATE}"
      fi
      printf "SUMMARY:%s\nLOCATION:%s\nDESCRIPTION:%s\nEND:VEVENT\n" \
             "${SUMMARY//$'\n'/\\n}" "${LOC//$'\n'/\\n}" "${DESC//$'\n'/\\n}"
    fi        
  else
    OCCURRENC_ITEMS=`sqlite3 "${CALENDAR_DB_DESTINATION_FILE}" "select day,occurrence_date,occurrence_start_date,occurrence_end_date from OccurrenceCache where event_id = ${EVENT_ID};"`        
    for ocItem in ${OCCURRENC_ITEMS[@]}
    do
      OC_DAY_RAW=`extractField ${ocItem} 1`
      OC_DATE_RAW=`extractField ${ocItem} 2`
      OC_START_DATE_RAW=`extractField ${ocItem} 3`
      OC_END_DATE_RAW=`extractField ${ocItem} 4`
  
      OC_DAY=`convertMacAbsoluteTime $OC_DAY_RAW`
      OC_DATE=`convertMacAbsoluteTime $OC_DATE_RAW`
      #OC_START_DATE=`convertMacAbsoluteTime $OC_START_DATE_RAW`
      OC_END_DATE=`convertMacAbsoluteTime $OC_END_DATE_RAW`
  
      #echo "#############################"
      #echo $OC_DAY
      #echo $OC_DATE
      #echo $OC_START_DATE
      #echo $OC_END_DATE
      #echo "==========> ${CALENDAR_START_MAC}<${OC_DATE_RAW%.*}<${CALENDAR_END_MAC} DEBUG_OC: ${ocItem}"
      if [[ ${CALENDAR_START_MAC} -le ${OC_DATE_RAW%.*} ]] && [[ ${CALENDAR_END_MAC} -ge ${OC_DATE_RAW%.*} ]] ; then
        printf "BEGIN:VEVENT\nUID:%s\nDTSTAMP;TZID=Europe/Berlin:%s\n" \
               "${ITEM}-${OC_DATE}" "${LAST_MODIFIED}" 
        if [[ $ALL_DAY == "1" ]]; then
          printf "DTSTART;TZID=Europe/Berlin;VALUE=DATE:%s\n" \
                 "${OC_DATE:0:8}" 
        else
          printf "DTSTART;TZID=Europe/Berlin:%s\nDTEND;TZID=Europe/Berlin:%s\n" \
                 "${OC_DATE}" "${OC_END_DATE}" 
        fi
        printf "SUMMARY:%s\nLOCATION:%s\nDESCRIPTION:%s\nEND:VEVENT\n" \
               "${SUMMARY//$'\n'/\\n}" "${LOC//$'\n'/\\n}" "${DESC//$'\n'/\\n}" 
      fi
      done   
  fi 
done

output_ical_footer

} | fold_long_lines 

# Restore the Input File Separator
IFS=$oldIFS
