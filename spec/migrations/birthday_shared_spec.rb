# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118120000_add_birthday_shared_to_rpg_club_users.rb")

# api#399: sharing a Birthday is off for every member, including those who
# already had a Birth Date.
RSpec.describe AddBirthdaySharedToRpgClubUsers do
  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    RpgClubUser.reset_column_information
  end

  after { RpgClubUser.reset_column_information }

  it "leaves every existing Birthday unshared" do
    migrate(:down)
    dated = create(:user, birth_date: BirthDate.new(month: 5, day: 4, year: 1990)).user_id
    undated = create(:user).user_id

    migrate(:up)

    expect(RpgClubUser.find(dated)).to have_attributes(birth_date: BirthDate.new(month: 5, day: 4, year: 1990),
      birthday_shared: false)
    expect(RpgClubUser.find(undated).birthday_shared).to be(false)
  end
end
