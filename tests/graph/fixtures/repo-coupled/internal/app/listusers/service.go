package listusers

import (
	"example.com/acme/internal/domain/user"
	"example.com/acme/internal/ports/user_repository"
)

type Service struct{ repo user_repository.Port }
func (s Service) List() []user.User { return nil }
