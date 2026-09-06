package user

import "example.com/acme/internal/adapters/postgres"

type User struct{ ID string; r postgres.Repo }
