# frozen_string_literal: true

# A member's Birth Date (spec #376, ticket #380) and the limit on changing it.
# Its year is optional (api#398, ADR 0011): a BirthDate of a month, a day and
# maybe a year. The member may share its Birthday, the day and month
# (api#399).
#
# A member may set or change their own Birth Date at most CHANGES_PER_MONTH
# times per calendar month in the club's time zone, and entering it the first
# time counts. Staff (Moderators and above) may set anyone's at any time;
# their changes are recorded but never count toward the member's limit.
# Setting the date it already has changes nothing and counts for nothing.
module BirthDates
  CHANGES_PER_MONTH = 2
  EARLIEST = Date.new(1900, 1, 1)
  # The year a Birth Date without one is checked against, so 29 February is a
  # real day.
  LEAP_YEAR = 2000
  DATED = /\A(?<year>\d{4})-(?<month>\d{1,2})-(?<day>\d{1,2})\z/
  YEARLESS = /\A(?<month>\d{1,2})-(?<day>\d{1,2})\z/
  NOT_A_DATE = "birth_date must be a date (YYYY-MM-DD, or MM-DD without the year)"

  # A member's own change refused because they used both of this month's.
  class LimitReached < StandardError
    attr_reader :next_change_on

    def initialize(next_change_on)
      @next_change_on = next_change_on
      super("You can change your Birth Date twice a month, and you've already changed it twice this month. " \
            "You can change it again on #{next_change_on.strftime('%-d %B %Y')}.")
    end
  end

  # A Birth Date that is not a real date in the past, or a month and day
  # that don't exist.
  class Invalid < StandardError; end

  # Sharing a Birthday (api#399) for a member with no Birth Date.
  class BirthDateRequired < StandardError
    def code = "birth_date_required"

    def initialize = super("Enter your Birth Date before you share your Birthday.")
  end

  module_function

  # The member's Birth Date and how many changes they have left this month,
  # as the API serves it. `user` may be nil (a member with no record yet).
  def document(user_id, user, now: Time.current)
    left = changes_left(user_id, now: now)
    {
      user_id: user_id.to_s,
      birth_date: user&.birth_date&.to_s,
      birthday_shared: user&.birthday_shared == true,
      changes_left_this_month: left,
      next_change_on: left.zero? ? next_month_start(now).iso8601 : nil
    }
  end

  # Sets (or, with nil, removes) the member's Birth Date. `by` is the Discord
  # user id of whoever changed it (nil for the bot without one), `staff`
  # whether they are a Moderator or above. Returns whether it changed.
  # Raises Invalid for a bad date and LimitReached for a member's third change
  # in a month.
  def change!(user, value, by:, staff:, now: Time.current)
    birth_date = parse(value, now: now)

    user.with_lock do
      next false if user.birth_date == birth_date

      if !staff && changes_left(user.user_id, now: now).zero?
        raise LimitReached, next_month_start(now)
      end

      if birth_date.nil?
        # Removing the Birth Date stops sharing its Birthday.
        user.update!(birth_date: nil, birthday_shared: false)
      else
        user.update!(birth_date: birth_date)
      end
      MemberBirthDateChange.create!(user_id: user.user_id, birth_date: birth_date, changed_by: by, by_staff: staff,
        changed_at: now)
      true
    end
  end

  # Turns sharing the member's Birthday (the day and month of their Birth
  # Date) on or off (api#399). Who may do which is the caller's to check: only
  # the member turns it on, staff may turn it off. Never recorded as a Birth
  # Date change, so it never counts toward the limit. Raises
  # BirthDateRequired turning it on without a Birth Date.
  def share!(user, shared)
    user.with_lock do
      raise BirthDateRequired if shared && user.birth_date.nil?

      user.update!(birthday_shared: shared)
    end
  end

  def changes_left(user_id, now: Time.current)
    used = MemberBirthDateChange.by_member.where(user_id: user_id.to_s, changed_at: month(now)).count
    [ CHANGES_PER_MONTH - used, 0 ].max
  end

  # The calendar month `now` falls in, in the club's time zone (ClubDay).
  def month(now)
    local = now.in_time_zone(ClubDay::TIME_ZONE)
    local.beginning_of_month..local.end_of_month
  end

  def next_month_start(now)
    ClubDay.today(now).next_month.beginning_of_month
  end

  # nil removes the Birth Date. Anything else is a YYYY-MM-DD date between
  # 1900 and today in the club's time zone, or an MM-DD month and day that
  # exist in some year (29 February included). Returns a BirthDate.
  def parse(value, now:)
    return nil if value.nil?

    match = DATED.match(value.to_s) || YEARLESS.match(value.to_s)
    raise Invalid, NOT_A_DATE unless match

    year = match.names.include?("year") ? match[:year].to_i : nil
    birth_date = BirthDate.new(month: match[:month].to_i, day: match[:day].to_i, year: year)
    check!(birth_date, now)
    birth_date
  end

  def check!(birth_date, now)
    raise Invalid, NOT_A_DATE unless Date.valid_date?(birth_date.year || LEAP_YEAR, birth_date.month, birth_date.day)
    return unless birth_date.year?

    date = Date.new(birth_date.year, birth_date.month, birth_date.day)
    raise Invalid, "birth_date can't be in the future" if date > ClubDay.today(now)
    raise Invalid, "birth_date can't be before #{EARLIEST.year}" if date < EARLIEST
  end
end
