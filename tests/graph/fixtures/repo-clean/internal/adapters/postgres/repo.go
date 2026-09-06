package postgres

import "example.com/acme/internal/ports/user_repository"

var _ user_repository.Port = Repo{}
type Repo struct{}
