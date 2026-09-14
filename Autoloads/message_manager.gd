extends Node
const LOG_TAG := "Message"


signal toast_requested(text: String, type: String)

func show(text: String, type: String = "info"):
	toast_requested.emit(text, type)
