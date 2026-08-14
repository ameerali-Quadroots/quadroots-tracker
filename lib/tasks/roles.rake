namespace :roles do
  desc "Seed roles, departments and permissions, then backfill users onto them. DRY_RUN=true to preview."
  task seed_and_backfill: :environment do
    RoleSeeder.call(dry_run: ENV["DRY_RUN"] == "true")
  end

  desc "Derive an initial reports-to tree from the existing department/role structure. DRY_RUN=true to preview."
  task bootstrap_hierarchy: :environment do
    HierarchyBootstrapper.call(dry_run: ENV["DRY_RUN"] == "true")
  end

  desc "Seed default approval flows and backfill approvals for existing requests. DRY_RUN=true to preview."
  task seed_approval_flows: :environment do
    ApprovalFlowSeeder.call(dry_run: ENV["DRY_RUN"] == "true")
  end

  desc "Re-sync only the permission catalogue after editing Permission::RESOURCES / PAGES."
  task sync_permissions: :environment do
    puts "Permissions in catalogue: #{Permission.sync_catalogue!}"
  end
end
