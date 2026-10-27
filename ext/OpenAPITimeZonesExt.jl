# TimeZones extension: zoned date-time codecs for generated OpenAPI modules
# emitted with `datetime = :zoned` or `:as_written` (their `using TimeZones` loads this).
module OpenAPITimeZonesExt

using TimeZones, Dates
import OpenAPI.Runtime:
    _as_written_zoned, _decode, _decode_as_written, _encode, _encode_as_written, DecodeError

function _decode(::Type{TimeZones.ZonedDateTime}, value::AbstractString)
    matched = match(
        r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})?$",
        value,
    )
    matched === nothing && throw(DecodeError("invalid RFC 3339 date-time $(repr(value))"))
    try
        clock = Dates.DateTime(matched.captures[1])
        fraction = matched.captures[2]
        if fraction !== nothing
            clock += Dates.Millisecond(
                parse(Int, rpad(first(fraction, min(3, length(fraction))), 3, '0')),
            )
        end
        zone = matched.captures[3]
        timezone = if zone === nothing || zone == "Z"
            TimeZones.tz"UTC"
        else
            sign = startswith(zone, '+') ? 1 : -1
            hours = parse(Int, zone[2:3])
            minutes = parse(Int, zone[5:6])
            TimeZones.FixedTimeZone(zone, sign * (3600 * hours + 60 * minutes))
        end
        return TimeZones.ZonedDateTime(clock, timezone)
    catch error
        error isa DecodeError && rethrow()
        throw(DecodeError("invalid RFC 3339 date-time: $(sprint(showerror, error))"))
    end
end
_encode(value::TimeZones.ZonedDateTime) =
    Dates.format(value, TimeZones.ISOZonedDateTimeFormat)

_as_written_zoned(::Type{TimeZones.ZonedDateTime}) = true

_with_fraction(clock::Dates.DateTime, ::Nothing) = clock
function _with_fraction(clock::Dates.DateTime, fraction::AbstractString)
    milliseconds = parse(Int, rpad(first(fraction, min(3, length(fraction))), 3, '0'))
    return clock + Dates.Millisecond(milliseconds)
end

_as_written(clock::Dates.DateTime, ::Nothing, ::Nothing) = clock
function _as_written(clock::Dates.DateTime, ::AbstractString, ::Nothing)
    return TimeZones.ZonedDateTime(clock, TimeZones.tz"UTC")
end
function _as_written(clock::Dates.DateTime, ::Nothing, offset::AbstractString)
    sign = parse(Int, offset[1:1] * "1")
    hours = parse(Int, offset[2:3])
    minutes = parse(Int, offset[5:6])
    zone = TimeZones.FixedTimeZone(offset, sign * (3600 * hours + 60 * minutes))
    return TimeZones.ZonedDateTime(clock, zone)
end

function _decode_as_written(value::AbstractString)
    matched = match(
        r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(?:(Z)|([+-]\d{2}:\d{2}))?$",
        value,
    )
    matched === nothing && throw(DecodeError("invalid RFC 3339 date-time $(repr(value))"))
    try
        clock = _with_fraction(Dates.DateTime(matched.captures[1]), matched.captures[2])
        return _as_written(clock, matched.captures[3], matched.captures[4])
    catch error
        error isa DecodeError && rethrow()
        throw(DecodeError("invalid RFC 3339 date-time: $(sprint(showerror, error))"))
    end
end

_encode_as_written(value::TimeZones.ZonedDateTime) = _encode(value)

end # module OpenAPITimeZonesExt
