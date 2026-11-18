# frozen_string_literal: true

# A member's Birth Date (spec #376, ticket #380) and the limit on changing it.
#
# A member may set or change their own Birth Date at most CHANGES_PER_MONTH
# times per calendar month in the club's time zone, and entering it the first
# time counts. Staff (Moderators and above) may set anyone's at any time;
# their changes are recorded but never count toward the member's limit.
# Setting the date it already has changes nothing and counts for nothing.
module BirthDates
  CHANGES_PER_MONTH = 2
  EARLIEST = Date.new(1900, 1, 1)

  # A member's own change refused because they used both of this month's.
  class LimitReached < StandardError
    attr_reader :next_change_on

    def initialize(next_change_on)
      @next_change_on = next_change_on
      super("You can change your Birth Date twice a month, and you've already changed it twice this month. " \
            "You can change it again on #{next_change_on.strftime('%-d %B %Y')}.")
    end
  end

  # A Birth Date that is not a real date in the past.
  class Invalid < StandardError; end

  module_function

  # The member's Birth Date and how many changes they have left this month,
  # as the API serves it. `user` may be nil (a member with no record yet).
  def document(user_id, user, now: Time.current)
    left = changes_left(user_id, now: now)
    {
      user_id: user_id.to_s,
      birth_date: user&.birth_date&.iso8601,
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
    date = parse(value, now: now)

    user.with_lock do
      next false if user.birth_date == date

      if !staff && changes_left(user.user_id, now: now).zero?
        raise LimitReached, next_month_start(now)
      end

      user.update!(birth_date: date)
      MemberBirthDateChange.create!(user_id: user.user_id, birth_date: date, changed_by: by, by_staff: staff,
        changed_at: now)
      true
    end
  end

  def changes_left(user_id, now: Time.current)
    used = MemberBirthDateChange.by_member.where(user_id: user_id.to_s, changed_at: month(now)).count
    [ CHANGES_PER_MONTH - used, 0 ].max
  end

  # The calendar month `now` falls in, in the club's time zone (the one
  # Challenge dates use).
  def month(now)
    local = now.in_time_zone(Challenges::TIME_ZONE)
    local.beginning_of_month..local.end_of_month
  end

  def next_month_start(now)
    Challenges.today(now).next_month.beginning_of_month
  end

  # nil removes the Birth Date; anything else must be a YYYY-MM-DD date
  # between 1900 and today in the club's time zone.
  def parse(value, now:)
    return nil if value.nil?

    date = Date.strptime(value.to_s, "%Y-%m-%d")
    raise Invalid, "birth_date can't be in the future" if date > Challenges.today(now)
    raise Invalid, "birth_date can't be before #{EARLIEST.year}" if date < EARLIEST

    date
  rescue Date::Error
    raise Invalid, "birth_date must be a date (YYYY-MM-DD)"
  end
end
