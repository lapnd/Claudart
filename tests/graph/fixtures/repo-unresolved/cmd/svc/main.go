package main

import (
	"example.com/acme/internal/adapters/postgres"
	"example.com/acme/internal/adapters/smtp"
	"example.com/acme/internal/app/listusers"
)

func main() { _ = postgres.Repo{}; _ = smtp.Mailer{}; _ = listusers.Service{} }
