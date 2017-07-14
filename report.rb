require 'date'

# A base exception
class WorkLogBaseException < RuntimeError
end

# Signals mismatch between the report header and filename
class ReportDateMismatch < WorkLogBaseException
end

# Raised when there is no Worklog Report file to read from.
class ReportFileNotFound < WorkLogBaseException
end

# A Header object for a Report.
class ReportHeader
  attr_reader :date, :location, :text

  def initialize(text)
    @date = @location = nil
    @text = text
    parse
  end

  # Parse the report header and fills in the report's attributes
  # @return [WorkLog::ReportHeader]
  def parse
    _re = /^Activity\s+Report\s*(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})\s+\((?<location>[^)]+)\)$/
    (_year, _month, _day, @location) =
      _re.match(@text, &:captures)
    @date = Date.new(year=_year.to_i, month=_month.to_i, mday=_day.to_i)
    self
  end

  def to_s
    @text
  end
end

# Representation of a WorkLog Journal Entry line
class ReportEntry
  attr_reader :tags

  def initialize(text = '')
    @todo_flag = false
    @tags = Hash.new(0)
    @text = text
    parse
  end

  # Parse this Entry's text field
  # @return [ReportEntry]
  def parse
    @todo_flag = !@text.scan(/\(TODO\)/).empty?
    @text
      .scan(/\[([A-Za-z]+)\]/)
      .reject(&:nil?)
      .map(&:first)
      .each { |i| @tags[i] += 1 }
    self
  end

  # True if this entry is a to-do item.
  # @return [TrueClass,FalseClass]
  def todo?
    @todo_flag
  end

  def tag_names
    @tags.keys
  end
end


# A WorkLog Report representing one day's of work.
class Report

  WORKLOG_ROOT = '/Users/luis/Documents/Worklog'.freeze

  # Static method to calculate the File
  # @return [String]
  def self.filename_for_date(dt = Date.today)
    "#{WORKLOG_ROOT}/#{dt.strftime('%Y/%m/%Y%m%d.report')}"
  end

  attr_reader :filename, :header, :entries

  # @param [Date] dt - the report date
  # @param [String] worklog_root - the Work Log root directory
  def initialize(dt = Date.today)
    raise ArgumentError unless dt.class == Date
    @date = dt
    @filename = Report.filename_for_date(@date)
    @header = nil
    @entries = []
    raise ReportFileNotFound unless ::File.exists?(@filename)
    ::File.open(@filename) do |f|
      @header = ReportHeader.new(f.readline)
      raise ReportDateMismatch unless @header.date == @date
      @entries = f.readlines.map { |l| ReportEntry.new(l)}
    end
  end
end


# Statistics about the Worklog Reports.
class ReportStatistics

  def initialize(start_date = Date.today.prev_month, end_date = Date.today)
    @start_date = start_date
    @end_date = end_date
    @tags = Hash.new(0)
    @total_events = 0
    calculate_statistics
  end

  def reports_enum
    Enumerator.new do |y|
      d = @start_date.clone
      loop do
        raise StopIteration if d > @end_date
        begin
          r = Report.new(d)
          y << r
        rescue ReportFileNotFound
          # Ignore
        end
        d = d.next_day
      end
    end
  end

  def calculate_statistics
    (reports_enum.map(&:entries).map {|a| a.map(&:tags)})
      .flatten.each { |e| @tags.merge!(e) {|k,o,n| o + n} }
    @total_events = @tags.values.inject(:+)
  end

  def to_s
    @tags.each.sort_by {|x| x[1]}.reverse.map { |k, v|
      "\n\tTeam %s: %d (%0.2f%%)" % [
        k, v, v.zero? ? 0 : 100 * v.to_f / @total_events
      ]
    }.inject("Events between #{@start_date} and #{@end_date}:", :+)
  end
end

puts ReportStatistics.new