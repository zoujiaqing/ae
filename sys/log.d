/**
 * Logging support.
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 *   Simon Arlott
 */

module ae.sys.log;

import std.datetime;
import std.file;
import std.path;
import std.stdio;
import std.string;

import ae.sys.file;

import ae.utils.textout;
import ae.utils.time;

string logDir;

private void init()
{
	import core.runtime;

	if (!logDir)
		logDir = Runtime.args[0].absolutePath().dirName().buildPath("logs");
}

shared static this() { init(); }
static this() { init(); }

enum TIME_FORMAT = "Y.m.d H:i:s.E";

private SysTime getLogTime()
{
	return Clock.currTime(UTC());
}

abstract class Logger
{
public:
	alias log opCall;

	this(string name)
	{
		this.name = name;
		open();
	}

	abstract Logger log(string str);

	void rename(string name)
	{
		close();
		this.name = name;
		open();
	}

	void close() {}

protected:
	string name;

	void open() {}
	void reopen() {}
}

class RawFileLogger : Logger
{
	bool timestampedFilenames;

	this(string name, bool timestampedFilenames = false)
	{
		this.timestampedFilenames = timestampedFilenames;
		super(name);
	}

	private final void logStartLine()
	{
	/+
		if (!f.isOpen) // hack
		{
			if (fileName is null)
				throw new Exception("Can't write to a closed log");
			reopen();
			RawFileLogger.log(str);
			close();
			return this;
		}
	+/
	}

	private final void logFragment(in char[] str)
	{
		f.write(str);
	}

	private final void logEndLine()
	{
		f.writeln();
		f.flush();
	}

	override Logger log(string str)
	{
		logStartLine();
		logFragment(str);
		logEndLine();
		return this;
	}

protected:
	string fileName;
	File f;

	override void open()
	{
		// name may contain directory separators
		string path = buildPath(logDir, name);
		auto base = path.baseName();
		auto dir = path.dirName();

		auto t = getLogTime();
		string timestamp = timestampedFilenames ? format(" %02d-%02d-%02d", t.hour, t.minute, t.second) : null;
		fileName = buildPath(dir, format("%04d-%02d-%02d%s - %s.log", t.year, t.month, t.day, timestamp, base));
		ensurePathExists(fileName);
		f = File(fileName, "ab");
	}

	override void reopen()
	{
		f = File(fileName, "ab");
	}
}

class FileLogger : RawFileLogger
{
	this(string name, bool timestampedFilenames = false)
	{
		super(name, timestampedFilenames);
	}

	override Logger log(string str)
	{
		auto ut = getLogTime();
		if (ut.day != currentDay)
		{
			f.writeln("\n---- (continued in next day's log) ----");
			f.close();
			open();
			f.writeln("---- (continued from previous day's log) ----\n");
		}

		enum TIMEBUFSIZE = 1 + timeFormatSize(TIME_FORMAT) + 2;
		static char[TIMEBUFSIZE] buf = "[";
		auto writer = BlindWriter!char(buf.ptr+1);
		putTime(writer, TIME_FORMAT, ut);
		writer.put(']');
		writer.put(' ');

		super.logStartLine();
		super.logFragment(buf[0..writer.ptr-buf.ptr]);
		super.logFragment(str);
		super.logEndLine();

		return this;
	}

	override void close()
	{
		//assert(f !is null);
		if (f.isOpen)
			f.close();
	}

private:
	int currentDay;

protected:
	final override void open()
	{
		super.open();
		currentDay = getLogTime().day;
		f.writef("\n\n--------------- %s ---------------\n\n\n", formatTime(TIME_FORMAT, getLogTime()));
		f.flush();
	}

	final override void reopen()
	{
		super.reopen();
		f.writef("\n\n--------------- %s ---------------\n\n\n", formatTime(TIME_FORMAT, getLogTime()));
		f.flush();
	}
}

class ConsoleLogger : Logger
{
	this(string name)
	{
		super(name);
	}

	override Logger log(string str)
	{
		string output = name ~ ": " ~ str ~ "\n";
		stderr.write(output);
		stderr.flush();
		return this;
	}
}

class NullLogger : Logger
{
	this() { super(null); }
	override Logger log(string str) { return this; }
}

class MultiLogger : Logger
{
	this(Logger[] loggers ...)
	{
		this.loggers = loggers.dup;
		super(null);
	}

	override Logger log(string str)
	{
		foreach (logger; loggers)
			logger.log(str);
		return this;
	}

	override void rename(string name)
	{
		foreach (logger; loggers)
			logger.rename(name);
	}

	override void close()
	{
		foreach (logger; loggers)
			logger.close();
	}

private:
	Logger[] loggers;
}

class FileAndConsoleLogger : MultiLogger
{
	this(string name)
	{
		super(new FileLogger(name), new ConsoleLogger(name));
	}
}
