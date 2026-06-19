#!/usr/bin/env bash

# Tests the get_codes.sh script.

response=$(./get_codes.sh --test)

# Pull the "arg" (code) value out of each Alfred item, in order.
ARG_REGEX='"arg": "([^"]+)"'
received_codes=()
while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ $ARG_REGEX ]]; then
        received_codes+=("${BASH_REMATCH[1]}")
    fi
done <<< "$response"

# Expected codes, one per line.
valid_responses=()
while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line ]] && valid_responses+=("$line")
done < test_messages_results.txt

escape_xml() {
    local s=$1
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    s=${s//\"/&quot;}
    printf '%s' "$s"
}

test_results=""
failures=0
errors=0

# Compare across the longer of the two lists so missing/extra codes are caught.
total=${#valid_responses[@]}
[[ ${#received_codes[@]} -gt $total ]] && total=${#received_codes[@]}

index=0
while [[ $index -lt $total ]]; do
    valid_response=${valid_responses[$index]-}
    received_code=${received_codes[$index]-}

    if [[ $index -ge ${#received_codes[@]} ]]; then
        escaped=$(escape_xml "Expected '$valid_response', but no code was returned")
        test_results+="<testcase classname=\"get_codes.sh\" name=\"line$index\" time=\"0\">
            <failure message=\"missing code\" type=\"missingCode\">$escaped</failure>
            </testcase>\n"
        printf "$index: \xE2\x9D\x8C missing code, expected '$valid_response'\n"
        let "errors+=1"
    elif [[ $index -ge ${#valid_responses[@]} ]]; then
        escaped=$(escape_xml "Unexpected extra code '$received_code'")
        test_results+="<testcase classname=\"get_codes.sh\" name=\"line$index\" time=\"0\">
            <failure message=\"extra code\" type=\"extraCode\">$escaped</failure>
            </testcase>\n"
        printf "$index: \xE2\x9D\x8C unexpected extra code '$received_code'\n"
        let "errors+=1"
    elif [[ $valid_response != "$received_code" ]]; then
        escaped=$(escape_xml "Expected '$valid_response', but received '$received_code'")
        test_results+="<testcase classname=\"get_codes.sh\" name=\"line$index\" time=\"0\">
            <failure message=\"invalid code\" type=\"invalidCode\">$escaped</failure>
            </testcase>\n"
        printf "$index: \xE2\x9D\x8C $valid_response != $received_code\n"
        let "failures+=1"
    else
        test_results+="<testcase classname=\"get_codes.sh\" name=\"line$index\" time=\"0\" />\n"
        printf "$index: \xE2\x9C\x85 $valid_response = $received_code\n"
    fi

    index=$((index + 1))
done

if [[ ($failures -eq 0) && ($errors -eq 0) ]]; then
    printf "\033[0;32mTest completed successfully.\033[0m\n"
else
    printf "\033[0;31m$failures failures, $errors errors.\033[0m\n"
fi

iso8601date=$(date -u +%Y-%m-%dT%H:%M:%S)
printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<testsuite name=\"get_codes.sh\" hostname=\"$HOSTNAME\" time=\"0\" timestamp=\"$iso8601date\"
    tests=\"$total\" errors=\"$errors\" failures=\"$failures\" skipped=\"0\">\n$test_results
</testsuite>" > "test_results.xml"

# Exit non-zero on any failure so `./test.sh` itself fails in CI.
[[ ($failures -eq 0) && ($errors -eq 0) ]]
