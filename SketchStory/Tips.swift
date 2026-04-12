import TipKit

struct CreateStoryButtonTip: Tip {
    static let createTapped = Event(id: "create-story-button-tapped")

    var title: Text {
        Text("Create your first story")
    }

    var message: Text? {
        Text("Tap + to start.")
    }

    var options: [any TipOption] {
        [
            MaxDisplayCount(1)
        ]
    }
}

struct StoryReaderAudioTip: Tip {
    static let audioTapped = Event(id: "story-reader-audio-tapped")

    var title: Text {
        Text("Play narration")
    }

    var message: Text? {
        Text("Tap play to hear the story.")
    }

    var options: [any TipOption] {
        [
            MaxDisplayCount(1)
        ]
    }
}

struct StoryReaderScrollTip: Tip {
    var title: Text {
        Text("Scroll down")
    }

    var message: Text? {
        Text("Swipe up to continue reading the next parts.")
    }

    var rules: [Rule] {
        [
            #Rule(StoryReaderAudioTip.audioTapped) {
                $0.donations.count > 0
            }
        ]
    }

    var options: [any TipOption] {
        [
            MaxDisplayCount(1)
        ]
    }
}

struct StoryPreviewSaveTip: Tip {
    var title: Text {
        Text("Save to unlock audio playback")
    }

    var message: Text? {
        Text("Save this story or chapter first, then use Play in the reader.")
    }

    var options: [any TipOption] {
        [
            MaxDisplayCount(1)
        ]
    }
}

struct StoryTypeSelectionTip: Tip {
    var title: Text {
        Text("Choose story or chapter")
    }

    var message: Text? {
        Text("Pick New Story to start fresh, or New Chapter to continue an existing one.")
    }

    var options: [any TipOption] {
        [
            MaxDisplayCount(1)
        ]
    }
}
