#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>

#import <stdbool.h>
#import <string.h>

struct options {
	FSEventStreamEventId startEventId;
	FSEventStreamEventId stopEventId;
	FSEventStreamEventId lastIdForSentinelEvents;
	bool willStop;
	bool dummyHistory;
	bool printOnlyPaths;
	CFTimeInterval latency;
	NSArray* pathsToWatch;
};

struct eventFlags {
	bool none: 1;
	bool mustScanSubDirs: 1;
	bool userDropped: 1;
	bool kernelDropped: 1;
	bool eventIdsWrapped: 1;
	bool historyDone: 1;
	bool rootChanged: 1;
	bool mount: 1;
	bool unmount: 1;
};

struct eventFlags parseEventFlags(FSEventStreamEventFlags flags) {
	return (struct eventFlags) {
		.none = flags == kFSEventStreamEventFlagNone,
		.mustScanSubDirs = (flags & kFSEventStreamEventFlagMustScanSubDirs) != 0,
		.userDropped = (flags & kFSEventStreamEventFlagUserDropped) != 0,
		.kernelDropped = (flags & kFSEventStreamEventFlagKernelDropped) != 0,
		.eventIdsWrapped = (flags & kFSEventStreamEventFlagEventIdsWrapped) != 0,
		.historyDone = (flags & kFSEventStreamEventFlagHistoryDone) != 0,
		.rootChanged = (flags & kFSEventStreamEventFlagRootChanged) != 0,
		.mount = (flags & kFSEventStreamEventFlagMount) != 0,
		.unmount = (flags & kFSEventStreamEventFlagUnmount) != 0,
	};
}

void callback(ConstFSEventStreamRef streamRef, void * clientCallBackInfo, size_t numEvents, void * eventPaths, const FSEventStreamEventFlags* eventFlags, const FSEventStreamEventId* eventIds) {
	struct options * opts = (struct options *) clientCallBackInfo;
	
	for (int i = 0; i < numEvents; i += 1) {
		FSEventStreamEventId eventId = eventIds[i];
		struct eventFlags flags = parseEventFlags(eventFlags[i]);
		char * eventPath = ((char **) eventPaths)[i];
		
		if (!flags.mount && !flags.unmount) {
			if (opts->willStop && (eventId >= opts->stopEventId || opts->stopEventId == (kFSEventStreamEventIdSinceNow && flags.historyDone))) {
				CFRunLoopStop(CFRunLoopGetCurrent());
				break;
			} else if (!flags.historyDone) {
				if (opts->printOnlyPaths) {
					printf("%s\n", eventPath);
				} else {
					if (flags.rootChanged) {
						printf("0x%016llx S %s/\n", opts->lastIdForSentinelEvents, eventPath);
					} else {
						char * flag = flags.mustScanSubDirs || flags.rootChanged ? "S" : "-";
						
						printf("0x%016llx %s %s\n", eventId, flag, eventPath);
						opts->lastIdForSentinelEvents = eventId;
					}
				}
			}
		}
	}
	
	fflush(stdout); // We alwys flush after delivering a batch.
}

void printUsage() {
	fprintf(stderr, "Usage: fsevents <options> <path> ...\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "Options:\n");
	fprintf(stderr, "    -h | --help: Print this help.\n");
	fprintf(stderr, "    -s <id> | --start <id>:\n");
	fprintf(stderr, "        Start replaying history from the next event after the given event id.\n");
	fprintf(stderr, "        `now' means to start with the next event without replaying history.'\n");
	fprintf(stderr, "        Specifying `eon' will simply print a single event with an `S' flag for\n");
	fprintf(stderr, "        each specified path. Defaults to `now'.\n");
	fprintf(stderr, "    -e <id> | --end <id>:\n");
	fprintf(stderr, "        Stop delivering events with the event with the given event id. `never'\n");
	fprintf(stderr, "        means to continue until the programm is stopped, `now' means to exit\n");
	fprintf(stderr, "        after replaying history. Defaults to `never'.\n");
	fprintf(stderr, "    -l <time> | --latency <time>:\n");
	fprintf(stderr, "        Time over which to accumulate events before delivering them batch-wise.\n");
	fprintf(stderr, "    -b | --bare:\n");
	fprintf(stderr, "        Print only the path of each event.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "Output:\n");
	fprintf(stderr, "    Without the --bare flag, every line is of the following form:\n");
	fprintf(stderr, "        <event-id> <flags> <path>\n");
	fprintf(stderr, "    \n");
	fprintf(stderr, "    <event-id>: Event as 16-digit hexadecimal number.\n");
	fprintf(stderr, "    <flags>: Flags for this event. Possible values:\n");
	fprintf(stderr, "        -: Normal event:\n");
	fprintf(stderr, "        S: Events somewhere inside this directory were dropped.\n");
	fprintf(stderr, "    <path>: The path of the folder in which the event occurred.\n");
}

struct options * parseOptions(int argc, char ** argv) {
	struct options * opts = malloc(sizeof (struct options)); // May leak if the function aborts.
	int pos = 1;
	
	opts->startEventId = kFSEventStreamEventIdSinceNow;
	opts->lastIdForSentinelEvents = FSEventsGetCurrentEventId();
	opts->willStop = false;
	opts->dummyHistory = false;
	opts->printOnlyPaths = false;
	opts->latency = 1.0;
	
	while (pos < argc && argv[pos][0] == '-') {
		if (strcmp(argv[pos], "-h") == 0 || strcmp(argv[pos], "--help") == 0) {
			return NULL;
		} else if (strcmp(argv[pos], "-s") == 0 || strcmp(argv[pos], "--start") == 0) {
			if (pos + 2 > argc) {
				fprintf(stderr, "Error: Option requires an argument: %s\n", argv[pos]);
				return NULL;
			}
			
			pos += 1;
			
			if (strcmp(argv[pos], "eon") == 0) {
				opts->dummyHistory = true;
				opts->startEventId = kFSEventStreamEventIdSinceNow;
			} else if (strcmp(argv[pos], "now") == 0) {
				opts->startEventId = kFSEventStreamEventIdSinceNow;
			} else {
				opts->startEventId = strtoimax(argv[pos], NULL, 0);
			}
		} else if (strcmp(argv[pos], "-e") == 0 || strcmp(argv[pos], "--end") == 0) {
			if (pos + 2 > argc) {
				fprintf(stderr, "Error: Option requires an argument: %s\n", argv[pos]);
				return NULL;
			}
			
			pos += 1;
			
			if (strcmp(argv[pos], "now") == 0) {
				opts->willStop = true;
				opts->stopEventId = kFSEventStreamEventIdSinceNow;
			} else if (strcmp(argv[pos], "never") != 0) {
				opts->willStop = true;
				opts->stopEventId = strtoimax(argv[pos], NULL, 0);
			}
		} else if (strcmp(argv[pos], "-l") == 0 || strcmp(argv[pos], "--latency") == 0) {
			if (pos + 2 > argc) {
				fprintf(stderr, "Error: Option requires an argument: %s\n", argv[pos]);
				return NULL;
			}
			
			pos += 1;
			opts->latency = strtof(argv[pos], NULL);
		} else if (strcmp(argv[pos], "-b") == 0 || strcmp(argv[pos], "--bare") == 0) {
			opts->printOnlyPaths = true;
		}
		
		pos += 1;
	}
	
	if (opts->printOnlyPaths && opts->dummyHistory) {
		fprintf(stderr, "Error: `--start eon' and `--bare' cannot be combined!\n");
		return NULL;
	}
	
	if (pos + 1 > argc) {
		fprintf(stderr, "Error: Pathes to watch expected after options!\n");
		return NULL;
	}
	
	NSMutableArray* paths = [NSMutableArray array];
	
	while (pos < argc) {
		[paths addObject:[NSString stringWithUTF8String:argv[pos]]];
		pos += 1;
	}
	
	opts->pathsToWatch = paths;
	
	return  opts;
}

int main (int argc, char ** argv) {
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	struct options * opts = parseOptions(argc, argv);
	struct FSEventStreamContext context = { .info = opts };
	FSEventStreamCreateFlags flags = kFSEventStreamCreateFlagNone;
	
	// Test for usage errors
	if (opts == NULL) {
		printUsage();
		return 1;
	}
	
	if (opts->dummyHistory) {
		for (NSString* path in opts->pathsToWatch)
			printf("0x%016llx S %s\n", opts->lastIdForSentinelEvents, [path UTF8String]);
		
		fflush(stdout); // We alwys flush after delivering a batch.
	}
	
	// When only printing dummy history, we'll not bother waiting for events
	if (!opts->dummyHistory || !opts->willStop || opts->stopEventId != kFSEventStreamEventIdSinceNow) {
		// As we're not printing any information about dropped events when printOnlyPaths is set, root changes aren't interesting
		if (!opts->printOnlyPaths)
			flags |= kFSEventStreamCreateFlagWatchRoot;
		
		/* Create the stream, passing in a callback */
		FSEventStreamRef stream = FSEventStreamCreate(NULL, callback, &context, (CFArrayRef)opts->pathsToWatch, opts->startEventId, opts->latency, flags);
		
		/* Create the stream before calling this. */
		FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		FSEventStreamStart(stream);
		CFRunLoopRun();
	}
	
	[pool drain];
	return 0;
}
