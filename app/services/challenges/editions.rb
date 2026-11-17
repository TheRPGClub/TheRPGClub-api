# frozen_string_literal: true

module Challenges
  # An Assignment Challenge's Editions (GLOSSARY.md, "Edition"; spec #376,
  # "Secret Santa"; ticket #383). Every date is the club's.
  #
  #   open_due!(challenge, today)   opens the Edition whose sign-up is due
  #   sign_up!(edition, user_id)    signs a member up before the cutoff
  #   withdraw!(edition, user_id)   withdraws them before the cutoff
  #   draw!(edition, now:, random:) the draw, at the cutoff
  #
  # Editions open by themselves: each one's sign-up opens the day after the
  # previous reveal (the first one's, the day the Challenge is created) and
  # lasts until its cutoff. An Edition whose cutoff passed before it could
  # open is skipped. Its dates are fixed when it opens; a calendar change
  # applies from the next Edition, or moves one still in sign-up that nobody
  # has joined.
  #
  # Sign-up needs BACKLOG_MINIMUM games in the member's backlog, so their
  # Santa has a real choice, and so does the draw, which leaves out whoever
  # fell below it by then and DMs them. The rest go round one random circle
  # (Challenges::Draw), each getting a Run of the Edition; with fewer than 2
  # the Edition is cancelled.
  module Editions
    BACKLOG_MINIMUM = 5

    # The Edition whose sign-up is open on `today`, as dates
    # (Formats::Assignment::EditionDates), or nil when none is.
    def self.due(challenge, today)
      calendar = Formats::Assignment.load(challenge)
      dates = calendar.edition(calendar.year_on(today), opens_from: Challenges.today(challenge.created_at))
      dates if dates.signup_opens_on <= today && today < dates.signup_cutoff_on
    end

    # The Editions of the Assignment Challenges in `challenges` whose sign-up
    # is open on `today`.
    def self.in_signup_on(today, challenges = Challenge.all)
      ChallengeEdition.in_signup.where("signup_opens_on <= :today AND signup_cutoff_on > :today", today: today)
        .where(challenge_id: challenges.where(challenge_format: Formats::Assignment::KEY).select(:id))
    end

    # The first club date after `today` an Edition of `challenge` opens on.
    def self.next_opening_on(challenge, today)
      calendar = Formats::Assignment.load(challenge)
      calendar.edition(calendar.year_on(today)).reveal_on + 1
    end

    # Opens the Edition due on `today`, unless it is open already. Returns
    # the Edition opened, or nil.
    def self.open_due!(challenge, today)
      return unless challenge.challenge_format == Formats::Assignment::KEY && (dates = due(challenge, today))

      inserted = ChallengeEdition.insert_all([ { challenge_id: challenge.id, **dates.to_h } ],
        unique_by: :ux_challenge_editions_year, returning: %i[id])
      challenge.editions.reset
      ChallengeEdition.find(inserted.first["id"]) if inserted.any?
    end

    # The calendar changed: an Edition still in sign-up that nobody has
    # joined closes, so that the Edition due on the new dates opens instead.
    def self.calendar_changed!(challenge)
      challenge.editions.in_signup.where.missing(:signups).delete_all
      challenge.editions.reset
    end

    def self.sign_up!(edition, user_id, today: Challenges.today)
      edition.with_lock do
        refuse_closed!(edition, today)
        if edition.signups.exists?(user_id: user_id)
          raise SignupRefused.new("already_signed_up", "You're already signed up for the #{edition.year} Edition.")
        end

        count = backlog_count(user_id)
        if count < BACKLOG_MINIMUM
          raise SignupRefused.new("backlog_too_small", backlog_message(count), status: :unprocessable_content,
            minimum: BACKLOG_MINIMUM, backlog_count: count)
        end

        edition.signups.create!(user_id: user_id)
      end
      edition
    end

    def self.withdraw!(edition, user_id, today: Challenges.today)
      edition.with_lock do
        refuse_closed!(edition, today)
        signup = edition.signups.find_by(user_id: user_id)
        raise SignupRefused.new("not_signed_up", "You aren't signed up for the #{edition.year} Edition.") unless signup

        signup.destroy!
      end
      edition
    end

    # The draw, at the sign-up cutoff: members below the backlog minimum are
    # left out (and DM'd), the rest go round one circle and get a Run each;
    # with fewer than 2 left the Edition is cancelled. Announced, unless the
    # Challenge is hidden. Does nothing once the Edition is past sign-up.
    def self.draw!(edition, now:, random: Random.new)
      edition.with_lock do
        next unless edition.phase == "signup"

        signups = edition.signups.order(:id).to_a
        counts = backlog_counts(signups.map(&:user_id))
        left_out, eligible = signups.partition { |signup| counts.fetch(signup.user_id, 0) < BACKLOG_MINIMUM }
        left_out.each { |signup| signup.update!(left_out_at: now) }

        if eligible.size < 2
          edition.update!(phase: "cancelled", drawn_at: now)
        else
          circle = Draw.circle(eligible.map(&:user_id), random: random)
          eligible.each { |signup| signup.update!(recipient_user_id: circle.fetch(signup.user_id)) }
          eligible.each do |signup|
            ChallengeRun.create!(challenge_id: edition.challenge_id, edition: edition, user_id: signup.user_id,
              started_at: now)
          end
          edition.update!(phase: "picking", drawn_at: now)
        end
        left_out_counts = left_out.to_h { |signup| [ signup.user_id, counts.fetch(signup.user_id, 0) ] }
        DirectMessages.left_out_of_draw!(edition, left_out_counts)
        announce_draw(edition, joined: eligible.size, left_out: left_out.size)
      end
    end

    def self.announce_draw(edition, joined:, left_out:)
      return if edition.challenge.hidden?

      if edition.phase == "cancelled"
        Announcements.edition_cancelled!(edition, joined: joined, left_out: left_out)
      else
        Announcements.signup_closed!(edition, joined: joined, left_out: left_out)
      end
    end
    private_class_method :announce_draw

    def self.backlog_count(user_id) = UserGameBacklog.where(user_id: user_id).count

    def self.backlog_counts(user_ids) = UserGameBacklog.where(user_id: user_ids).group(:user_id).count

    def self.backlog_message(count)
      "You need at least #{BACKLOG_MINIMUM} games in your backlog to sign up, so your Santa has a real choice. " \
        "You have #{count}."
    end

    def self.refuse_closed!(edition, today)
      return if edition.signup_open?(today)

      raise SignupRefused.new("signup_closed",
        "Sign-up for the #{edition.year} Edition closed on #{edition.signup_cutoff_on.strftime('%-d %B %Y')}.")
    end
    private_class_method :refuse_closed!
  end
end
