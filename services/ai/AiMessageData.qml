import QtQuick;

/**
 * Represents a message in an AI conversation. (Kind of) follows the OpenAI API message structure.
 */
QtObject {
    property string role
    property string content
    property string rawContent
    property string fileMimeType
    property string fileUri
    property string localFilePath
    property string model
    property bool thinking: true
    property bool done: false
    property var annotations: []
    property var annotationSources: []
    property list<string> searchQueries: []
    property string functionName
    property var functionCall
    property string functionResponse
    property bool functionPending: false
    /** Provider-assigned id linking a tool call to its result. */
    property string toolCallId
    /** Name of the tool waiting for user approval, empty when nothing is pending. */
    property string pendingToolName
    /** Arguments for the tool waiting for user approval. */
    property var pendingToolArgs
    /** Human-readable summary of what the pending tool will do. */
    property string pendingToolSummary
    property bool visibleToUser: true
}
