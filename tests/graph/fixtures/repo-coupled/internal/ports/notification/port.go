package notification

import "example.com/acme/internal/domain/user"

type Port interface{ Notify(u user.User) error }
