#!/usr/bin/env bash
set -o errexit

ROW_REGEX='^\[?\{"ROWID"\:([[:digit:]]+),"sender"\:"([^"]+)","service"\:"([^"]+)","message_date"\:"([^"]+)","text"\:"([[:print:]][^\\]+)"\}.*$'
NUMBER_MATCH_REGEX='([G[:digit:]-]{3,})'

OUTPUT=""
LOOK_BACK_MINUTES=${LOOK_BACK_MINUTES:-15}
RERUN_INTERVAL=${RERUN_INTERVAL:-"0.5"}
DEBUG=false
TESTING=false

while true; do
  case "$1" in
    --debug)
      DEBUG=true
      set -o xtrace
      ;;
    --test)
      TESTING=true
      ;;
    --look-back-minutes)
      shift
      LOOK_BACK_MINUTES="$1"
      ;;
    --help)
      echo "Usage"
      echo "get_codes.sh [--help] [--test] [--look-back-minutes]"
      echo "    --help: show this message."
      echo "    --test: Run the script in test mode."
      echo "    --look-back-minutes: How many minutes until old messages are not shown. (default 15 minutes)"
      exit 0
      ;;
    -*)
      echo "ERROR: unknown option '$1'"
      $0 --help
      exit 1
      ;;
    *)
      break
      ;;
  esac
  shift
done

if [ "$TESTING" = true ]; then
    RESPONSE=$(cat test_messages.txt)
else
	SQL_QUERY=$(cat <<-EOF
	SELECT
		message.rowid,
		ifnull(handle.uncanonicalized_id, chat.chat_identifier) AS sender,
		message.service,
		datetime(message.date / 1000000000 + strftime('%s', '2001-01-01'), 'unixepoch', 'localtime') AS message_date,
		message.text
	FROM
		message
			LEFT JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
			LEFT JOIN chat ON chat.ROWID = chat_message_join.chat_id
			LEFT JOIN handle ON message.handle_id = handle.ROWID
	WHERE
		service_name = "SMS"
		AND message.is_from_me = 0
		AND message.text IS NOT NULL
		AND length(message.text) > 0
		AND (
			message.text GLOB '*[0-9][0-9][0-9]*'
			OR message.text GLOB '*[0-9][0-9][0-9][0-9]*'
			OR message.text GLOB '*[0-9][0-9][0-9][0-9][0-9]*'
			OR message.text GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9]*'
			OR message.text GLOB '*[0-9][0-9][0-9]-[0-9][0-9][0-9]*'
			OR message.text GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9]*'
			OR message.text GLOB '*[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*'
		)
		AND datetime(message.date / 1000000000 + strftime('%s', '2001-01-01'), 'unixepoch', 'localtime')
			>= datetime('now', '-$LOOK_BACK_MINUTES minutes', 'localtime')
	ORDER BY
		message.date DESC
	LIMIT 10;
	EOF
	)
	RESPONSE=$(sqlite3 ~/Library/Messages/chat.db -json "$SQL_QUERY")
fi

if [[ -z "$RESPONSE" ]]; then
    OUTPUT+=$(
    printf '{
            "rerun": "%s",
            "items": [{
                "type": "default",
                "icon": { "path": "icon.png", },
                "arg": "",
                "subtitle": "Searched messages in the last %s minutes.",
                "title": "No codes found",
            }]
        }' \
        "$LOOK_BACK_MINUTES" \
        "$RERUN_INTERVAL" \
    )
else
    OUTPUT+=$(printf '{"rerun": "%s", "items":[' $RERUN_INTERVAL)
    while read line; do
        if [[ $line =~ $ROW_REGEX ]]; then
            sender=${BASH_REMATCH[2]}
            message_date=${BASH_REMATCH[4]}
            message=${BASH_REMATCH[5]}
            remaining_message=$message
            message_quoted=${message/$'\n'}
            message_quoted=${message_quoted//[\"]/\\\"}

            while [[ $remaining_message =~ $NUMBER_MATCH_REGEX ]]; do
                code=${BASH_REMATCH[1]}
                OUTPUT+=$( \
                    printf '{
                        "type": "default",
                        "icon": { "path": "icon.png", },
                        "subtitle": "From %s at %s [%s]",
                        "title": "%s",
                        "arg": "%s",
                    },' \
                    "$sender" \
                    "$message_date" \
                    "$message_quoted" \
                    "$code" \
                    "$code" \
                )
                # Trim to the remaining message
                remaining_message=${remaining_message##*${BASH_REMATCH[0]}}
            done
        fi
    done <<< "$RESPONSE"
    OUTPUT+='],}'
fi

echo -e $OUTPUT
