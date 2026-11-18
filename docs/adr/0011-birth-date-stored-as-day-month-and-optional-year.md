# A Birth Date is stored as a day, a month and an optional year

A Birth Date used to be one `date` column, so it always carried a year. Birthdays let a member share only the day and month, and some members won't want to give the year at all, not even to staff. We now store the Birth Date as `birth_month`, `birth_day` and a nullable `birth_year`. We rejected keeping the date column with a placeholder year and a "year known" flag: it means less migration, but every reader of the column would have to know the placeholder year isn't real, and the first one to forget would show a member a birth year they never gave.

## Consequences

- Challenges reads `birth_year`. A Birth Date without a year counts as no birth year, so a birth-year Run still refuses with `birth_date_required`.
- A Birth Date may be 29 February with no year. Each consumer decides what that means in other years; Birthday Posts use 28 February.
- Upcoming Birthdays and the daily Birthday Post look members up by month and day directly, without parsing dates.
