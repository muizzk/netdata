# #No shebang necessary
# BASH Lib: Simple incoming webhook for slack integration.
# 
# The script expects the following parameters to be defined by the upper layer:
# SLACK_INCOMING_WEBHOOK_URL
# SLACK_BOT_NAME
# SLACK_CHANNEL
#
# Copyright:
#
# Author: Pavlos Emm. Katsoulakis <paul@netdata.cloud

post_message() {
	TYPE="$1"
	MESSAGE="$2"

	case "$TYPE" in
		"PLAIN_MESSAGE")
			curl -X POST --data-urlencode "payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_BOT_NAME}\", \"text\": \"${MESSAGE}\", \"icon_emoji\": \":space_invader:\"}" ${SLACK_INCOMING_WEBHOOK_URL}
			;;
		"RICH_MESSAGE")
			POST_MESSAGE="{
				\"text\": \"${MESSAGE}\",
				\"attachments\": [{
				    \"text\": \"Current build\",
				    \"fallback\": \"I could not determine the build\",
				    \"callback_id\": \"\",
				    \"color\": \"#3AA3E3\",
				    \"attachment_type\": \"default\",
				    \"actions\": [
					{
					    \"name\": \"${TRAVIS_BUILD_NUMBER}\",
					    \"text\": \"View build status\",
					    \"type\": \"button\",
					    \"url\": \"${TRAVIS_BUILD_WEB_URL}\"
					}]
				}]
			}"
			echo "Sending ${POST_MESSAGE}"
			curl -X POST --data-urlencode "payload=${POST_MESSAGE}" "${SLACK_INCOMING_WEBHOOK_URL}"
			;;
	esac
}
