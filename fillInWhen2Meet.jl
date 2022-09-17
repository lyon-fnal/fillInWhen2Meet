# fillInWeb2Meet.jl
# Adam Lyon 2022-09 lyon at fnal dot gov
#
# Fill in blocks on a Web2Meet poll that are free according to one's calendar
#
# Use the python interface to selenium and the Chrome driver
# conda install selenium
# brew install chromedriver
#
# You also need a Mac Shortcut called "find-busy-times"

using PyCall
wd = pyimport("selenium.webdriver")

using TimeZones
using Chain
using Dates
using CSV
using Logging

struct CalendarEntry
    startAt::Time
    endAt::Time
    title::String
end
isDuringEvent(event::CalendarEntry, t::Time) = t >= event.startAt && t < event.endAt

"""
    getCalEntries(dt)

    Get the calendar entries for a date using the Mac shortcut find-busy-times
"""
function getCalEntries(dt::DateTime)
    inFile, inIO = mktemp()  # These files will be deleted at the end of the application
    outFile = tempname()

    @info "Checking calendar for $(Date(dt))"

    # The shortcut wants a file containing the date to check
    write(inIO, Dates.format(dt, "YYYY-mm-dd"))
    close(inIO)

    # Run the shortcuts command
    cmd = `shortcuts run find-busy-times -i $inFile -o $outFile`
    run(cmd)

    calEntries = Array{CalendarEntry,1}[]

    # Did we get a file? If not, then there were no events on that day
    if isfile(outFile)
        entries = CSV.File(outFile, header=["s", "e", "t"])
        calEntries = [CalendarEntry(r.s, r.e, r.t) for r in entries]
    end

    return calEntries
end # function getCalEntries

function main()

    # Open the automated Chrome
    dvr = wd.Chrome()

    # Tell the user to navigate to their When2Meet page
    println("Navigate to the When2Meet page and sign in")
    println("Press Enter when completed")
    readline()

    # Get the Your Grid Slots div
    ygs = try
        dvr.find_element(wd.common.by.By.ID, "YouGridSlots")
    catch e
        error("Your availability grid was not found. Are you on a When2Meet page?")
    end

    # Get all the divs in the grid
    divs = ygs.find_elements(wd.common.by.By.TAG_NAME, "div")

    # Check that the divs are displayed
    divs[1].is_displayed() || error("Your availability grid is not displayed. You didn't sign in.")

    # Start with an empty calendar
    # cal is a dictionary that will hold a vector of CalendarEntry's for a date
    cal = Dict()

    # Get the first day of this week in case we need it (Julia says the first day of the week is Monday)
    thisMonday = firstdayofweek(now())

    # Loop over the divs
    for div in divs
        # Do we have a data-time attribute?
        dta = div.get_attribute("data-time")

        # Skip if this div doesn't have a data-time attribute (the div is a row header)
        dta === nothing && continue

        # dta is unix epoch time - convert to DateTime in Central Time Zone
        dt = parse(Int, dta) |> unix2datetime

        # If the year is before 2000, then it's a "day" When2Meet and not for specific days. Change date to this week
        if year(dt) < 2000
            nd = if dayofweek(dt) == Dates.Monday
                        thisMonday
                 else
                    tonext(thisMonday, dayofweek(dt))
            end
            dt = DateTime(year(nd), month(nd), day(nd), hour(dt), minute(dt), second(dt))
        else
            # If this is a specific date, then we need to adjust the timezone
            dt = ZonedDateTime(dt, tz"America/Chicago", from_utc=true) |> DateTime
        end

        # Have we looked at the calendar for this date?
        theDate = Date(dt)
        if ! haskey(cal, theDate)
            # We need to get the calendar entries for this day
            cal[theDate] = getCalEntries(dt)
        end

        # Are we in any calendar event for the date/time?
        hasConflict = @chain isDuringEvent.(cal[theDate], Time(dt)) any

        # If we don't have a conflict, then click the div to mark it as available
        ! hasConflict && div.click()

    end # for div in divs

end # function main

main()