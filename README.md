# Pingdom to Graphite

A script to allow you to copy metrics from Pingdom to graphite. Pingdom,
although allowing access to  effective all your metrics through the API, does
have some limits in place to prevent abuse. This script tries to be mindful of
that, although does provide a "backfill" option if you care to burn up your
daily api limit in one fell swoop.

## Usage

The utility itself will provide detailed help for all the commands if you just
invoke it by itself:

    pingdom-to-graphite

### For the Impatient

Ok, so you don't like reading command line help. Here's how to get up and
running quickly:

    pingdom-to-graphite init

Will place a sample config file into the default location `~/.p2g/config.json`.
Don't worry scripters, this location can be overriden with the `-c` switch. Drop
your pingdom credentials and graphite settings into there to enable the script
to do any actual work.

    pingdom-to-graphite init_checks

This will pre-fill the pingdom->checks setting in your config file with a list
of all your available checks.

    pingdom-to-graphite update

Will pull the 100 most recent checks for each check specified in your config
file and create a  `~/.p2g/state.json` file storing a few key timestamps about
what data you've successfully send to graphite. Similar to the config file, this
location can be overridden with the `-s` switch.

    pingdom-to-graphite update

"Hey, that's the same command!" you say. Indeed it is, and will run through your
checks picking up where we left of from the last update. If you stopped to check
graphite after that last step you might even pick up a few new checks. The idea
is just to scedule this job via cron and let  your metrics roll in on a fixed
schedule. How often? Well, you can't run any checks at more then  a minute
resolution, so going any more frequently then that is wasteful. The actual
limiting factor is that updating each metric is a separate API call, so the more
checks you want to pipe to graphite the less frequently you'll be able to run
the script. Want some numbers?

    pingdom-to-graphite advice

Will give you the rough API numbers you'd consume a day given your number of
monitored checks in five minute increments until it finds something that works.
However, keep in mind that you're not using this to do alerting (right, I mean,
that's what you're paying Pingdom for) and that graphite  doesn't have any
issues backfilling content, so picking the most aggressive value you can isn't
necessarily the best approach!

## License

The MIT License

Copyright (c) 2012 Lewis J. Goettner, III

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.