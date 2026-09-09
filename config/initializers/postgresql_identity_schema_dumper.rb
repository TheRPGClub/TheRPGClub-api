# frozen_string_literal: true

# Rails 8.1 recognizes PostgreSQL identity columns as database-generated at
# runtime, but its Ruby schema dumper only emits `serial`/`bigserial` for legacy
# serial columns. Without this adapter shim, identity primary keys are written
# as plain bigint columns with `default: nil`, and a database loaded from
# schema.rb cannot generate IDs.
require "active_record/schema_dumper"
require "active_record/connection_adapters/abstract/schema_dumper"
require "active_record/connection_adapters/postgresql/schema_dumper"

module PostgresqlIdentitySchemaDumper
  private

  def explicit_primary_key_default?(column)
    return false if column.identity?

    super
  end

  def schema_type(column)
    return super unless column.identity?

    column.bigint? ? :bigserial : :serial
  end

  def schema_expression(column)
    super unless column.identity?
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(PostgresqlIdentitySchemaDumper)
