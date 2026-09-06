import os


def leak():
    return os.getcwd()
