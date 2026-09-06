package user_repository

import "example.com/acme/internal/domain/user"

type Port interface{ Get(id string) (user.User, error) }
