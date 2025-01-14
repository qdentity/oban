defmodule Oban.Migrations.V09 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    alter table(:oban_jobs, prefix: prefix) do
      add_if_not_exists(:meta, :map, default: %{})
      add_if_not_exists(:cancelled_at, :utc_datetime_usec)
    end

    execute """
    DO $$
    DECLARE
      version int;
      already bool;
    BEGIN
      SELECT current_setting('server_version_num')::int INTO version;
      SELECT '{cancelled}' <@ enum_range(NULL::#{prefix}.oban_job_state)::text[] INTO already;

      IF already THEN
        RETURN;
      ELSIF version >= 120000 THEN
        ALTER TYPE #{prefix}.oban_job_state ADD VALUE IF NOT EXISTS 'cancelled';
      ELSE
        ALTER TYPE #{prefix}.oban_job_state RENAME TO old_oban_job_state;

        CREATE TYPE #{prefix}.oban_job_state AS ENUM (
          'available',
          'scheduled',
          'executing',
          'retryable',
          'completed',
          'discarded',
          'cancelled'
        );

        ALTER TABLE #{prefix}.oban_jobs RENAME column state TO _state;
        ALTER TABLE #{prefix}.oban_jobs ADD state #{prefix}.oban_job_state NOT NULL default 'available';

        UPDATE #{prefix}.oban_jobs SET state = _state::text::#{prefix}.oban_job_state;

        ALTER TABLE #{prefix}.oban_jobs DROP column _state;
        DROP TYPE #{prefix}.old_oban_job_state;
      END IF;
    END$$;
    """

    create_if_not_exists index(:oban_jobs, [:queue, :state, :priority, :scheduled_at, :id],
                           prefix: prefix
                         )
  end

  def down(%{prefix: prefix}) do
    alter table(:oban_jobs, prefix: prefix) do
      remove_if_exists(:meta, :map)
      remove_if_exists(:cancelled_at, :utc_datetime_usec)
    end

    execute """
    DO $$
    BEGIN
      UPDATE #{prefix}.oban_jobs SET state = 'discarded' WHERE state = 'cancelled';

      ALTER TYPE #{prefix}.oban_job_state RENAME TO old_oban_job_state;

      CREATE TYPE #{prefix}.oban_job_state AS ENUM (
        'available',
        'scheduled',
        'executing',
        'retryable',
        'completed',
        'discarded'
      );

      ALTER TABLE #{prefix}.oban_jobs RENAME column state TO _state;

      ALTER TABLE #{prefix}.oban_jobs ADD state #{prefix}.oban_job_state NOT NULL default 'available';

      UPDATE #{prefix}.oban_jobs SET state = _state::text::#{prefix}.oban_job_state;

      ALTER TABLE #{prefix}.oban_jobs DROP column _state;

      DROP TYPE #{prefix}.old_oban_job_state;
    END$$;
    """
  end
end
