# Ticket: ModelDeployment refuses to delete

A ModelDeployment created for a demo is stuck Terminating. The team
deleted it twenty minutes ago. kubectl shows it still there, with a
deletionTimestamp in the past.

(Prereq: module 50's operator deployed, and a ModelDeployment named
drill-demo in inference - inject.sh creates it if missing.)
