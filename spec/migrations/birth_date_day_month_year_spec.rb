# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118110000_split_birth_date_into_day_month_and_year.rb")

# api#398 (ADR 0011): a Birth Date is stored as a month, a day and an optional
# year. Every existing Birth Date, and every recorded Birth Date change, keeps
# its day, month and year.
RSpec.describe SplitBirthDateIntoDayMonthAndYear do
  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    [ RpgClubUser, MemberBirthDateChange ].each(&:reset_column_information)
  end

  def connection = ActiveRecord::Base.connection

  after { [ RpgClubUser, MemberBirthDateChange ].each(&:reset_column_information) }

  it "keeps each existing Birth Date's day, month and year" do
    migrate(:down)
    dated = create(:user).user_id
    undated = create(:user).user_id
    connection.execute("UPDATE rpg_club_users SET birth_date = '1990-05-04' WHERE user_id = '#{dated}'")
    connection.execute(<<~SQL.squish)
      INSERT INTO member_birth_date_changes (user_id, birth_date, by_staff, changed_at)
      VALUES ('#{dated}', '1996-02-29', false, now()), ('#{dated}', NULL, false, now())
    SQL

    migrate(:up)

    expect(RpgClubUser.find(dated).birth_date).to eq(BirthDate.new(month: 5, day: 4, year: 1990))
    expect(RpgClubUser.find(undated).birth_date).to be_nil
    expect(MemberBirthDateChange.where(user_id: dated).order(:id).map(&:birth_date))
      .to eq([ BirthDate.new(month: 2, day: 29, year: 1996), nil ])
  end

  it "puts dated Birth Dates back on the way down" do
    member = create(:user, birth_date: BirthDate.new(month: 5, day: 4, year: 1990)).user_id

    migrate(:down)

    expect(connection.select_value("SELECT birth_date FROM rpg_club_users WHERE user_id = '#{member}'"))
      .to eq(Date.new(1990, 5, 4))
  ensure
    migrate(:up)
  end
end
