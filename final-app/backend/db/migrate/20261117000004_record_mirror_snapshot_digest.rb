class RecordMirrorSnapshotDigest < ActiveRecord::Migration[8.1]
  def change
    add_column "desk.source_sync", :snapshot_digest, :string
  end
end
