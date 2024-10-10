## RESTful API Implementation

## Abstract:
This project proposes the development of a proof of concept and implementation of a RESTful API for the ERP system. Currently, the ERP system is supported by database objects within a PostgreSQL database. Introducing a RESTful API on top of the existing database offers numerous benefits, including improved interoperability, maintenance, and flexibility. By providing a quick and responsive interface, this API aims to meet the growing needs of the ERP system and serve as the foundation for next-generation applications for students, faculty, and staff.

## Key Components:
- **API:** The RESTful API will serve as the primary interface for interacting with the AUN ERP system.
- **PostgREST:** Leveraging PostgREST to automatically generate a RESTful API from the PostgreSQL database schema.
- **PostgreSQL:** Utilizing PostgreSQL as the underlying database management system for storing ERP data.
- **ERP System:** Integrating the API with the existing ERP system to enhance its functionality and accessibility.

## Purpose:
The purpose of this project is to enhance the ERP system by implementing a modern and efficient RESTful API. By doing so, we aim to improve interoperability, simplify maintenance tasks, and provide a more flexible interface for users. This API will cater to the evolving needs of students, faculty, and staff at, laying the groundwork for future advancements and innovations in ERP application development.

## Features:
- Expose CRUD (Create, Read, Update, Delete) operations for ERP data entities via HTTP endpoints.
- Implement authentication and authorization mechanisms to ensure secure access to sensitive data.
- Support for filtering, sorting, and pagination to enhance usability and performance.
- Documentation generation for API endpoints to facilitate usage and integration with client applications.
- Integration with existing ERP modules to streamline workflow processes and data management.

## Database Configuration:

To configure the database, follow these steps:

1. **Install PostgreSQL:** Ensure that PostgreSQL is installed on your system.

2. **Run the Database Script:** Execute the `database.sql` file to recreate the necessary database schema. You can do this using the following command:
    ```
    psql -U <username> -d <database_name> -f database.sql
    ```
    Replace `<username>` with your PostgreSQL username and `<database_name>` with the desired database name.

3. **Start PostgREST:** After setting up the database, start the PostgREST server by running the following command:
    ```
    postgrest postgrest/postgrest.conf
    ```
    This command will start the PostgREST server using the configuration provided in the `postgrest.postgrest.conf` file.

Ensure that you have the necessary permissions and dependencies installed to execute these commands.

For further assistance or troubleshooting, refer to the PostgreSQL and PostgREST documentation or contact the project maintainer.

## Installation:
1. Clone the repository.
2. Install dependencies using `pip install -r requirements.txt`.
3. Configure database connection settings in `postgrest/postgrest.conf`.
4. Migrate the database with `python manage.py migrate`.
6. Run the application using `python manage.py runserver`.

## Usage:
1. Access the API endpoints using HTTP requests (GET, POST, PUT, DELETE).
2. Authenticate using [authentication method] to access restricted endpoints.
3. Refer to the API documentation for details on available endpoints and request/response formats.

## Contributing:
Contributions to the project are welcome! Please follow the guidelines outlined in [CONTRIBUTING.md] to contribute code, report issues, or suggest improvements.

## Contact:
For inquiries or assistance, please contact Najeeb Yusuf at yusufnajlawal@gmail.com.

