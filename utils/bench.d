/**
 * Simple benchmarking/profiling code
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 */

module ae.utils.bench;

import std.datetime;

TickDuration lastTime;

static this()
{
	lastTime = TickDuration.currSystemTick();
}

TickDuration elapsedTime()
{
	auto c = TickDuration.currSystemTick();
	auto d = c - lastTime;
	lastTime = c;
	return d;
}

struct TimedAction
{
	string name;
	TickDuration duration;

	@property long ticks() { return duration.length; }
}

TimedAction[] timedActions;
size_t[string] timeNameIndices;
string currentAction = null;

void timeEnd(string action = null)
{
	if (action && currentAction && action != currentAction)
		action = currentAction ~ " / " ~ action;
	if (action is null)
		action = currentAction;
	if (action is null)
		action = "other";
	currentAction = null;

	// ordered
	if (action !in timeNameIndices)
	{
		timeNameIndices[action] = timedActions.length;
		timedActions ~= TimedAction(action, elapsedTime());
	}
	else
		timedActions[timeNameIndices[action]].duration += elapsedTime();
}


void timeStart(string action = null)
{
	timeEnd();
	currentAction = action;
}

void timeAction(string action, void delegate() p)
{
	timeStart(action);
	p();
	timeEnd(action);
}

void clearTimes()
{
	timedActions = null;
	timeNameIndices = null;
	lastTime = TickDuration.currSystemTick();
}

/// Retrieves current times and clears them.
string getTimes()()
{
	timeEnd();

	import std.string, std.array;
	string[] lines;
	int maxLength;
	foreach (action; timedActions)
		if (action.ticks)
			if (maxLength < action.name.length)
				maxLength = action.name.length;
	string fmt = format("%%%ds : %%10d (%%s)", maxLength);
	foreach (action; timedActions)
		if (action.ticks)
			lines ~= format(fmt, action.name, action.ticks, dur!"hnsecs"(action.ticks));
	clearTimes();
	return join(lines, "\n");
}

void dumpTimes()()
{
	import std.stdio;
	import ae.sys.console;
	auto times = getTimes();
	if (times.length)
		writeln(times);
}

private string[] timeStack;

void timePush(string action = null)
{
	timeStack ~= currentAction;
	timeStart(action);
}

void timePop(string action = null)
{
	timeEnd(action);
	timeStart(timeStack[$-1]);
	timeStack = timeStack[0..$-1];
}
