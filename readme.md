# fsevents

Simple command line tool to query the macOS fsevents database. It can reprt past events as well as continuously report new events.


## Usage

	Usage: fsevents <options> <path> ...
	
	Options:
		 -h | --help: Print this help.
		 -s <id> | --start <id>:
			  Start replaying history from the next event after the given event id.
			  `now' means to start with the next event without replaying history.'
			  Specifying `eon' will simply print a single event with an `S' flag for
			  each specified path. Defaults to `now'.
		 -e <id> | --end <id>:
			  Stop delivering events with the event with the given event id. `never'
			  means to continue until the programm is stopped, `now' means to exit
			  after replaying history. Defaults to `never'.
		 -l <time> | --latency <time>:
			  Time over which to accumulate events before delivering them batch-wise.
		 -b | --bare:
			  Print only the path of each event.
	
	Output:
		 Without the --bare flag, every line is of the following form:
			  <event-id> <flags> <path>
		 
		 <event-id>: Event as 16-digit hexadecimal number.
		 <flags>: Flags for this event. Possible values:
			  -: Normal event:
			  S: Events somewhere inside this directory were dropped.
		 <path>: The path of the folder in which the event occurred.
